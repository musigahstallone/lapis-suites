import crypto from 'crypto'
import { Router, Request, Response } from 'express'
import jwt from 'jsonwebtoken'
import { getDb } from '../db'
import {
  JWT_SECRET,
  generateHexObjectId,
  getClientIp,
  normalizeKenyanPhone,
  maskKenyanPhone
} from '../config'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { createRateLimiter } from '../middleware/rateLimiter'
import { logServerEvent } from '../middleware/logger'
import { sendSms } from '../services/sms'
import { checkAndSendDueReminders } from '../services/reminders'
import { runTenantLedgerReconciliation } from './tenants'
import { initiateKcbStkPushCore } from './kcb'

const router = Router()
const publicOtpLimiter = createRateLimiter(8, 60 * 1000)
const publicStkLimiter = createRateLimiter(8, 60 * 1000)

const OTP_TTL_MS = 10 * 60 * 1000
const OTP_MAX_ATTEMPTS = 5

function generateOtpCode(): string {
  return crypto.randomInt(100000, 1000000).toString()
}

function hashOtp(code: string): string {
  return crypto.createHash('sha256').update(`public-pay:${code}:${JWT_SECRET}`).digest('hex')
}

function phonesMatch(a?: string, b?: string): boolean {
  const normA = normalizeKenyanPhone(a || '')
  const normB = normalizeKenyanPhone(b || '')
  if (!normA || !normB) return false
  return normA.slice(-9) === normB.slice(-9)
}

function extractPaySession(req: Request): any | null {
  const authHeader = req.headers['authorization']
  const headerToken = authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : null
  const token = headerToken || req.body?.paySessionToken || req.query?.paySessionToken
  if (!token) return null
  try {
    const decoded: any = jwt.verify(String(token), JWT_SECRET)
    if (decoded.purpose !== 'public_pay_session' || !decoded.tenantId) return null
    return decoded
  } catch {
    return null
  }
}

/**
 * Helper to record a link click (deduping rapid double hits within 5 seconds)
 */
export async function recordPaymentLinkClick(linkId: string, ip?: string, userAgent?: string) {
  const db = getDb()
  const link = await db.collection('payment_links').findOne({ linkId })
  if (!link) return null

  const now = new Date()
  const nowIso = now.toISOString()
  const lastClickedMs = link.lastClickedAt ? new Date(link.lastClickedAt).getTime() : 0
  const isDuplicateBurst = lastClickedMs > 0 && (now.getTime() - lastClickedMs) < 5000

  if (!isDuplicateBurst) {
    const nextStatus = link.status === 'sent' ? 'clicked' : link.status
    await db.collection('payment_links').updateOne(
      { linkId },
      {
        $inc: { clickCount: 1 },
        $set: {
          clickedAt: link.clickedAt || nowIso,
          lastClickedAt: nowIso,
          lastClickIp: ip || null,
          lastClickUserAgent: userAgent ? userAgent.slice(0, 160) : null,
          status: nextStatus,
          updatedAt: nowIso
        }
      }
    )
    logServerEvent('PAY-LINK', `Click tracked: linkId=${linkId} | Unit ${link.unitNumber} (${link.tenantName}) | clicks=${(link.clickCount || 0) + 1}`)
  }

  return await db.collection('payment_links').findOne({ linkId }, { projection: { _id: 0 } })
}

/**
 * GET /api/public-pay/link/:linkId
 * Public endpoint returning ONLY safe non-sensitive preview metadata (first name & unit number).
 * NEVER exposes phone numbers (not even masked) and never prematurely states "already paid";
 * residents verify their phone via OTP and go straight to their live balance.
 */
router.get('/public-pay/link/:linkId', async (req: Request, res: Response) => {
  try {
    const linkId = String(req.params.linkId || '').trim()
    if (!linkId) return res.status(400).json({ error: 'Payment link ID is required.' })

    const link = await recordPaymentLinkClick(linkId, getClientIp(req), String(req.headers['user-agent'] || ''))
    if (!link) {
      return res.status(404).json({ error: 'This payment link was not found or is invalid.' })
    }

    const firstName = String(link.tenantName || 'Resident').split(' ')[0]

    res.json({
      ok: true,
      linkId: link.linkId,
      propertyName: 'LAPIS SUITES',
      firstName,
      unitNumber: link.unitNumber,
      status: link.status
    })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

/**
 * POST /api/public-pay/request-otp
 * Verifies the phone belongs to the specific link's tenant (or looks up tenant by phone on generic /pay)
 * and sends a 6-digit MobileSasa SMS OTP. Never leaks phone digits or prefixes on mismatch.
 */
router.post('/public-pay/request-otp', publicOtpLimiter, async (req: Request, res: Response) => {
  try {
    const db = getDb()
    const { phone, linkId } = req.body
    if (!phone) {
      return res.status(400).json({ error: 'Please enter your registered mobile phone number.' })
    }

    const normalizedPhone = normalizeKenyanPhone(String(phone))
    if (!/^254[17]\d{8}$/.test(normalizedPhone)) {
      return res.status(400).json({ error: 'Please enter a valid 9-digit Kenyan mobile number starting with 7 or 1.' })
    }

    let tenant: any = null
    let linkDoc: any = null

    if (linkId) {
      linkDoc = await db.collection('payment_links').findOne({ linkId: String(linkId).trim() })
      if (!linkDoc) {
        return res.status(404).json({ error: 'Payment link not found.' })
      }
      if (!phonesMatch(normalizedPhone, linkDoc.tenantPhone)) {
        logServerEvent('SECURITY', `Phone mismatch on payment link ${linkId}`)
        return res.status(403).json({
          error: 'That phone number does not match the registered number for this unit. Please check and try again.'
        })
      }
      tenant = await db.collection('tenants').findOne({ id: linkDoc.tenantId })
    } else {
      const last9 = normalizedPhone.slice(-9)
      tenant = await db.collection('tenants').findOne({
        $or: [
          { phone: normalizedPhone },
          { phone: `+${normalizedPhone}` },
          { phone: `0${last9}` },
          { phone: { $regex: `${last9}$` } }
        ]
      })
    }

    if (!tenant) {
      return res.status(404).json({ error: 'No active resident account was found for that phone number.' })
    }

    const otpCode = generateOtpCode()
    const challengeId = generateHexObjectId()
    const nowIso = new Date().toISOString()
    const expiresAt = new Date(Date.now() + OTP_TTL_MS).toISOString()

    const smsResult = await sendSms({
      phone: normalizedPhone,
      message: `Lapis Suites Rent Pay OTP: ${otpCode}. Valid for 10 minutes. Enter this code to view your arrears and pay via M-Pesa.`,
      purpose: 'payment_link_otp',
      recipientEmail: tenant.email,
      userId: tenant.id,
      meta: { linkId: linkDoc?.linkId || null, unitNumber: tenant.currentUnitNumber }
    })

    if (!smsResult.ok) {
      return res.status(502).json({
        error: smsResult.error || 'Failed to dispatch SMS OTP. Please try again.'
      })
    }

    await db.collection('public_pay_otps').insertOne({
      challengeId,
      tenantId: tenant.id,
      linkId: linkDoc?.linkId || null,
      phone: normalizedPhone,
      otpHash: hashOtp(otpCode),
      attempts: 0,
      used: false,
      expiresAt,
      createdAt: nowIso
    })

    if (linkDoc) {
      await db.collection('payment_links').updateOne(
        { linkId: linkDoc.linkId },
        { $set: { otpRequestedAt: nowIso, updatedAt: nowIso } }
      )
    }

    const challengeToken = jwt.sign(
      { purpose: 'public_pay_otp', challengeId, tenantId: tenant.id, linkId: linkDoc?.linkId || null },
      JWT_SECRET,
      { expiresIn: '10m' }
    )

    logServerEvent('PAY-LINK', `Dispatched public pay OTP (tenant=${tenant.name}, linkId=${linkDoc?.linkId || 'direct'})`)

    res.json({
      ok: true,
      challengeToken,
      expiresInSeconds: Math.floor(OTP_TTL_MS / 1000),
      message: 'A 6-digit verification code has been sent via SMS to your registered phone.'
    })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

/**
 * POST /api/public-pay/verify-otp
 * Verifies the 6-digit SMS OTP and returns a short-lived paySessionToken + ONLY this tenant's live arrears.
 */
router.post('/public-pay/verify-otp', publicOtpLimiter, async (req: Request, res: Response) => {
  try {
    const db = getDb()
    const { challengeToken, code } = req.body
    if (!challengeToken || !code) {
      return res.status(400).json({ error: 'Verification session and 6-digit OTP are required.' })
    }

    let decoded: any
    try {
      decoded = jwt.verify(String(challengeToken), JWT_SECRET)
    } catch {
      return res.status(401).json({ error: 'OTP session expired. Please request a new code.' })
    }

    if (decoded.purpose !== 'public_pay_otp' || !decoded.challengeId) {
      return res.status(401).json({ error: 'Invalid verification session.' })
    }

    const otpDoc = await db.collection('public_pay_otps').findOne({ challengeId: decoded.challengeId })
    if (!otpDoc || otpDoc.used) {
      return res.status(400).json({ error: 'This verification code has already been used or is invalid.' })
    }

    if (new Date(otpDoc.expiresAt).getTime() < Date.now()) {
      return res.status(400).json({ error: 'OTP has expired. Please request a new code.' })
    }

    if (Number(otpDoc.attempts || 0) >= OTP_MAX_ATTEMPTS) {
      return res.status(429).json({ error: 'Maximum OTP attempts reached. Please request a new code.' })
    }

    const cleanCode = String(code).replace(/\D/g, '').trim()
    if (cleanCode.length !== 6 || hashOtp(cleanCode) !== otpDoc.otpHash) {
      await db.collection('public_pay_otps').updateOne(
        { challengeId: otpDoc.challengeId },
        { $inc: { attempts: 1 } }
      )
      const remaining = Math.max(0, OTP_MAX_ATTEMPTS - (Number(otpDoc.attempts || 0) + 1))
      return res.status(400).json({
        error: remaining > 0
          ? `Incorrect OTP code. ${remaining} attempt${remaining === 1 ? '' : 's'} remaining.`
          : 'Incorrect OTP code. Please request a new code.'
      })
    }

    const nowIso = new Date().toISOString()
    await db.collection('public_pay_otps').updateOne(
      { challengeId: otpDoc.challengeId },
      { $set: { used: true, verifiedAt: nowIso } }
    )

    if (otpDoc.linkId) {
      await db.collection('payment_links').updateOne(
        { linkId: otpDoc.linkId, status: { $nin: ['paid', 'partial'] } },
        { $set: { status: 'verified', otpVerifiedAt: nowIso, updatedAt: nowIso } }
      )
    }

    // Fetch live reconciled account standing ONLY for this verified tenant
    const rec = await runTenantLedgerReconciliation(otpDoc.tenantId)
    const tenant = rec.tenant
    const lease = rec.lease
    const unitNumber = tenant?.currentUnitNumber || lease?.unitNumber || ''

    const recentPayments = await db.collection('transactions')
      .find({ tenantId: otpDoc.tenantId }, { projection: { _id: 0, id: 1, reference: 1, amount: 1, date: 1, method: 1, status: 1 } })
      .sort({ date: -1, timestamp: -1 })
      .limit(5)
      .toArray()

    const paySessionToken = jwt.sign(
      {
        purpose: 'public_pay_session',
        tenantId: otpDoc.tenantId,
        leaseId: lease?.id || null,
        unitNumber,
        phone: otpDoc.phone,
        linkId: otpDoc.linkId || null
      },
      JWT_SECRET,
      { expiresIn: '30m' }
    )

    logServerEvent('PAY-LINK', `Public pay OTP verified for ${tenant?.name} (Unit ${unitNumber}, linkId=${otpDoc.linkId || 'direct'})`)

    res.json({
      ok: true,
      paySessionToken,
      linkId: otpDoc.linkId || null,
      account: {
        tenantId: tenant?.id,
        tenantName: tenant?.name || 'Resident',
        unitNumber,
        phone: otpDoc.phone,
        maskedPhone: maskKenyanPhone(otpDoc.phone),
        leaseNumber: lease?.leaseNumber || '',
        monthlyRent: Number(lease?.monthlyRent || 0),
        depositAmount: Number(lease?.depositAmount || 0),
        depositPaid: Boolean(rec.summary?.depositPaid),
        balance: Math.round(Number(rec.summary?.balance || 0)),
        arrearsBalance: Math.round(Number(rec.summary?.balance || 0)),
        accountCredit: Math.round(Number(rec.summary?.accountCredit || 0)),
        nextPaymentDueDate: rec.summary?.nextPaymentDueDate || lease?.nextPaymentDueDate || '',
        recentPayments
      }
    })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

/**
 * POST /api/public-pay/stkpush
 * Protected by verified `paySessionToken`. Strictly charges for the verified tenant's unit & links to `linkId`.
 */
router.post('/public-pay/stkpush', publicStkLimiter, async (req: Request, res: Response) => {
  try {
    const session = extractPaySession(req)
    if (!session) {
      return res.status(401).json({ error: 'Payment session expired. Please verify your phone with a fresh SMS OTP.' })
    }

    const db = getDb()
    const tenant = await db.collection('tenants').findOne({ id: session.tenantId })
    if (!tenant) {
      return res.status(404).json({ error: 'Resident profile not found.' })
    }

    const amount = Math.round(Number(req.body?.amount || 0))
    const mpesaPhone = String(req.body?.phoneNumber || session.phone || tenant.phone || '').trim()
    if (!amount || amount <= 0) {
      return res.status(400).json({ error: 'Please enter a valid payment amount greater than KES 0.' })
    }

    const unitNumber = session.unitNumber || tenant.currentUnitNumber || 'Suite'
    const result = await initiateKcbStkPushCore({
      phoneNumber: mpesaPhone,
      amount,
      invoiceNumber: `LAPIS-${unitNumber}`,
      description: `Rent Unit ${unitNumber}`,
      callerName: tenant.name,
      callerEmail: tenant.email,
      callerRole: 'public_otp_resident',
      callerIp: getClientIp(req),
      tenantId: tenant.id,
      unitNumber,
      paymentLinkId: session.linkId || null
    })

    if (session.linkId && result.checkoutRequestId) {
      await db.collection('payment_links').updateOne(
        { linkId: session.linkId },
        { $set: { checkoutRequestId: result.checkoutRequestId, updatedAt: new Date().toISOString() } }
      )
    }

    res.json(result)
  } catch (err: any) {
    res.status(err.status || 500).json({ error: err.message || 'Failed to initiate M-Pesa STK Push.' })
  }
})

/**
 * POST /api/public-pay/status
 * Checks STK Push status and returns refreshed live arrears for the verified session.
 */
router.post('/public-pay/status', async (req: Request, res: Response) => {
  try {
    const session = extractPaySession(req)
    if (!session) {
      return res.status(401).json({ error: 'Payment session expired.' })
    }

    const db = getDb()
    const { checkoutRequestId, merchantRequestId } = req.body
    const query: any = {}
    if (checkoutRequestId) query.checkoutRequestId = checkoutRequestId
    if (merchantRequestId) query.merchantRequestId = merchantRequestId

    const tx = Object.keys(query).length > 0 ? await db.collection('kcb_transactions').findOne(query) : null
    let updatedStanding = null
    if (tx?.status === 'Success') {
      try {
        const rec = await runTenantLedgerReconciliation(session.tenantId)
        updatedStanding = {
          balance: Math.round(Number(rec.summary?.balance || 0)),
          accountCredit: Math.round(Number(rec.summary?.accountCredit || 0)),
          nextPaymentDueDate: rec.summary?.nextPaymentDueDate || ''
        }
      } catch {}
    }

    res.json({
      status: tx?.status || 'Pending',
      statusDescription: tx?.statusDescription || '',
      resultDesc: tx?.resultDesc || '',
      mpesaReceiptNumber: tx?.mpesaReceiptNumber || '',
      amount: tx?.amount || 0,
      updatedStanding
    })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

/**
 * GET /api/reminders/links (Admin only)
 * Returns all tracked rent reminder links enriched with MobileSasa DLR delivery status and funnel metrics.
 */
router.get('/reminders/links', authenticateToken, requireRole(['landlord']), async (_req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const links = await db.collection('payment_links')
      .find({}, { projection: { _id: 0 } })
      .sort({ createdAt: -1 })
      .limit(150)
      .toArray()

    // Enrich with MobileSasa DLR status from sms_logs
    const trackingIds = links.map((l: any) => l.smsTrackingId).filter(Boolean)
    const smsMap = new Map<string, any>()
    if (trackingIds.length > 0) {
      const smsLogs = await db.collection('sms_logs')
        .find({ trackingId: { $in: trackingIds } }, { projection: { _id: 0, trackingId: 1, status: 1, deliveryStatus: 1, deliveryTime: 1, gateway: 1 } })
        .toArray()
      for (const s of smsLogs) {
        smsMap.set(s.trackingId, s)
      }
    }

    const enriched = links.map((l: any) => {
      const dlr = smsMap.get(l.smsTrackingId)
      return {
        ...l,
        smsDeliveryStatus: dlr?.status || l.smsStatus || 'Accepted',
        smsCarrierDetail: dlr?.deliveryStatus || null,
        smsDeliveredAt: dlr?.deliveryTime || null,
        smsGateway: dlr?.gateway || null
      }
    })

    const stats = {
      total: enriched.length,
      active: enriched.filter((l: any) => !['paid', 'expired'].includes(l.status)).length,
      partial: enriched.filter((l: any) => l.status === 'partial').length,
      clicked: enriched.filter((l: any) => (l.clickCount || 0) > 0 || ['clicked', 'verified', 'partial', 'paid'].includes(l.status)).length,
      verified: enriched.filter((l: any) => ['verified', 'partial', 'paid'].includes(l.status)).length,
      paid: enriched.filter((l: any) => l.status === 'paid').length,
      totalCollectedViaLinks: enriched.reduce((sum: number, l: any) => sum + Number(l.totalPaidViaLink ?? l.paidAmount ?? 0), 0)
    }

    res.json({ links: enriched, stats })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

/**
 * POST /api/reminders/run (Admin only)
 * Sends due rent reminders with unique tracked payment links to unpaid tenants (all or a specific tenantId).
 */
router.post('/reminders/run', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const { force = true, tenantId } = req.body || {}
    const result = await checkAndSendDueReminders({
      force: Boolean(force),
      tenantId: tenantId ? String(tenantId) : undefined,
      triggeredBy: req.user?.email || 'landlord'
    })
    res.json({ ok: true, ...result })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
