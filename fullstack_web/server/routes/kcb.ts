import crypto from 'crypto'
import jwt from 'jsonwebtoken'
import { Router, Request, Response } from 'express'
import { EventEmitter } from 'events'
import { getDb } from '../db'
import { KCB_CONFIG, JWT_SECRET, generateHexObjectId, getClientIp, normalizeKenyanPhone, maskKenyanPhone } from '../config'
import { authenticateToken, authenticateUserOrPaySession, requireRole, AuthRequest } from '../middleware/auth'
import { createRateLimiter } from '../middleware/rateLimiter'
import { logServerEvent } from '../middleware/logger'
import { broadcastServerEvent } from '../events'
import { runTenantLedgerReconciliation } from './tenants'
import { notifyAdminsSms, notifyTenantSms, sendSms } from '../services/sms'
import { recordPaymentAgainstActiveLink } from '../services/reminders'

const router = Router()
const callbackEmitter = new EventEmitter()
callbackEmitter.setMaxListeners(250)

let cachedKcbToken: { token: string; expiresAt: number } | null = null

async function getKcbAccessToken(): Promise<string> {
  const now = Date.now()
  if (cachedKcbToken && cachedKcbToken.expiresAt > now + 60000) {
    return cachedKcbToken.token
  }

  logServerEvent('KCB', 'Requesting fresh OAuth 2.0 access token from KCB Buni...')
  const credentials = Buffer.from(`${KCB_CONFIG.consumerKey}:${KCB_CONFIG.consumerSecret}`).toString('base64')

  const tokenUrl = `${KCB_CONFIG.baseUrl}/token`
  const params = new URLSearchParams()
  params.append('grant_type', 'client_credentials')

  const response = await fetch(tokenUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${credentials}`,
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: params.toString()
  })

  if (!response.ok) {
    const errorText = await response.text()
    throw new Error(`KCB token endpoint failed (${response.status}): ${errorText}`)
  }

  const data: any = await response.json()
  const accessToken = data.access_token || data.accessToken
  if (!accessToken) {
    throw new Error('KCB response did not contain access_token')
  }

  const expiresInSeconds = Number(data.expires_in || 3599)
  cachedKcbToken = {
    token: accessToken,
    expiresAt: now + (expiresInSeconds * 1000)
  }
  logServerEvent('KCB', 'Successfully acquired KCB OAuth token')
  return accessToken
}

export interface InitiateStkPushInput {
  phoneNumber: string
  amount: number
  invoiceNumber?: string
  description?: string
  callerName?: string
  callerEmail?: string
  callerRole?: string
  callerIp?: string
  tenantId?: string | null
  unitNumber?: string
  paymentLinkId?: string | null
}

export async function initiateKcbStkPushCore(input: InitiateStkPushInput) {
  const db = getDb()
  const { phoneNumber, amount, invoiceNumber, description, callerName, callerEmail, callerRole, callerIp, tenantId, unitNumber, paymentLinkId } = input

  if (!phoneNumber || !amount || Number(amount) <= 0) {
    throw Object.assign(new Error('A valid Kenyan phone number and positive amount are required.'), { status: 400 })
  }

  const normalizedPhone = normalizeKenyanPhone(phoneNumber)
  if (!/^254[17]\d{8}$/.test(normalizedPhone)) {
    throw Object.assign(new Error('Invalid phone number format. Must be a valid Safaricom/Kenyan mobile number (e.g. 0712345678 or 254712345678).'), { status: 400 })
  }

  const numericAmount = Math.round(Number(amount))
  const invoice = invoiceNumber ? String(invoiceNumber).trim() : `LAPIS-${unitNumber || 'RENT'}-${Date.now().toString().slice(-4)}`
  const desc = description ? String(description).slice(0, 30) : 'Rent Payment'
  const nowIso = new Date().toISOString()
  const recordId = generateHexObjectId()

  logServerEvent('KCB-STK', `Initiating STK Push for ${normalizedPhone} - KES ${numericAmount.toLocaleString()} (${invoice}) [Caller: ${callerName || 'Resident'}${paymentLinkId ? ` | Link: ${paymentLinkId}` : ''}]`)

  let checkoutRequestId: any = null
  let merchantRequestId: any = null
  let stkResponseData: any = null
  let pushSuccess = false
  let statusDescription = 'Initiated'

  try {
    const token = await getKcbAccessToken()
    const messageId = generateHexObjectId()

    const pushPayload = {
      amount: String(numericAmount),
      phoneNumber: normalizedPhone,
      sharedShortCode: true,
      invoiceNumber: invoice,
      callbackUrl: KCB_CONFIG.callbackUrl,
      transactionDescription: desc
    }

    const kcbRes = await fetch(`${KCB_CONFIG.baseUrl}/mm/api/request/1.0.0/stkpush`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'routeCode': KCB_CONFIG.defaultRouteCode || '200',
        'operation': 'STKPush',
        'messageId': messageId,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(pushPayload)
    })

    const rawKcb = await kcbRes.text()
    logServerEvent('KCB-STK', `KCB STK Raw Response (${kcbRes.status}): ${rawKcb}`)

    try {
      stkResponseData = JSON.parse(rawKcb)
    } catch {
      stkResponseData = { raw: rawKcb }
    }

    if (kcbRes.ok && stkResponseData) {
      checkoutRequestId = stkResponseData.response?.CheckoutRequestID ||
                          stkResponseData.response?.CheckoutRequestId ||
                          stkResponseData.CheckoutRequestID ||
                          stkResponseData.CheckoutRequestId ||
                          stkResponseData.checkoutRequestId ||
                          checkoutRequestId

      merchantRequestId = stkResponseData.response?.MerchantRequestID ||
                          stkResponseData.response?.MerchantRequestId ||
                          stkResponseData.MerchantRequestID ||
                          stkResponseData.MerchantRequestId ||
                          stkResponseData.merchantRequestId ||
                          merchantRequestId

      statusDescription = stkResponseData.response?.ResponseDescription ||
                          stkResponseData.header?.statusDescription ||
                          stkResponseData.ResponseDescription ||
                          'Success'
      pushSuccess = true
    } else {
      statusDescription = stkResponseData.header?.statusDescription || stkResponseData.response?.ResponseDescription || `KCB HTTP ${kcbRes.status}`
      pushSuccess = false
    }
  } catch (kcbErr: any) {
    logServerEvent('KCB-STK', `KCB STK Push request failed: ${kcbErr.message}`)
    statusDescription = `KCB Error: ${kcbErr.message}`
    pushSuccess = false
  }

  const kcbRecord = {
    id: recordId,
    merchantRequestId,
    checkoutRequestId,
    phoneNumber: normalizedPhone,
    amount: numericAmount,
    invoiceNumber: invoice,
    status: pushSuccess ? 'Pending' : 'Failed',
    statusCode: pushSuccess ? '0' : '500',
    statusDescription,
    callerName: callerName || 'Resident',
    callerEmail: callerEmail || 'resident@lapissuites.com',
    callerRole: callerRole || 'resident',
    callerIp: callerIp || '127.0.0.1',
    tenantId: tenantId || null,
    unitNumber: unitNumber || '',
    paymentLinkId: paymentLinkId || null,
    createdAt: nowIso,
    rawResponse: stkResponseData
  }

  await db.collection('kcb_transactions').insertOne(kcbRecord)
  logServerEvent('AUDIT', `KCB Transaction recorded [${merchantRequestId}]: ${normalizedPhone} -> KES ${numericAmount} (Status: ${kcbRecord.status})`)

  return {
    success: pushSuccess,
    merchantRequestId,
    checkoutRequestId,
    amount: numericAmount,
    phoneNumber: normalizedPhone,
    statusDescription,
    message: pushSuccess
      ? `STK Push prompt dispatched to ${normalizedPhone}. Please enter your M-Pesa PIN on your phone.`
      : `Failed to initiate STK Push: ${statusDescription}`
  }
}

// 1. Initiate STK Push (Protected by JWT + Rate Limiter; public pay uses /api/public-pay/stkpush with OTP session)
router.post(
  '/kcb/stkpush',
  authenticateToken,
  createRateLimiter(10, 60000), // Max 10 pushes per minute
  async (req: AuthRequest, res: Response) => {
    try {
      const user = req.user!
      const { phoneNumber, amount, invoiceNumber, description, callerName, callerEmail, tenantId, unitNumber, paymentLinkId } = req.body
      const isLandlord = user.role === 'landlord'
      const scopedTenantId = isLandlord ? tenantId : (user.tenantId || user.userId)
      const scopedUnitNumber = isLandlord ? unitNumber : (user.unitNumber || unitNumber)

      const result = await initiateKcbStkPushCore({
        phoneNumber,
        amount: Number(amount),
        invoiceNumber,
        description,
        callerName: callerName || user.name,
        callerEmail: callerEmail || user.email,
        callerRole: user.role,
        callerIp: getClientIp(req),
        tenantId: scopedTenantId,
        unitNumber: scopedUnitNumber,
        paymentLinkId
      })
      res.json(result)
    } catch (err: any) {
      logServerEvent('KCB-STK', `Unexpected error during STK Push: ${err.message}`)
      res.status(err.status || 500).json({ error: err.message || 'Internal server error during STK Push.' })
    }
  }
)

// 1b. Admin STK Push Step 1: Request SMS OTP to the logged-in admin's Settings phone
router.post(
  '/kcb/admin-stk/request-otp',
  authenticateToken,
  requireRole(['landlord']),
  createRateLimiter(8, 60000),
  async (req: AuthRequest, res: Response) => {
    try {
      const db = getDb()
      const adminEmail = (req.user?.email || '').toLowerCase()
      const adminDoc = await db.collection('users').findOne({ email: adminEmail, role: 'landlord' })
      const adminPhone = adminDoc?.phone ? normalizeKenyanPhone(adminDoc.phone) : ''

      if (!adminPhone || !/^254[17]\d{8}$/.test(adminPhone)) {
        return res.status(400).json({
          error: 'No admin mobile phone number is configured for your account. Go to Settings → Authorized Administrators and add your phone number first.'
        })
      }

      const amount = Math.round(Number(req.body?.amount || 0))
      const unitNumber = String(req.body?.unitNumber || '').trim()
      const tenantName = String(req.body?.tenantName || 'Resident').trim()

      if (!amount || amount <= 0) {
        return res.status(400).json({ error: 'Please specify a valid payment amount before requesting admin OTP.' })
      }

      const otpCode = crypto.randomInt(100000, 1000000).toString()
      const otpHash = crypto.createHash('sha256').update(`admin-stk:${otpCode}:${JWT_SECRET}`).digest('hex')
      const challengeId = generateHexObjectId()
      const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString()

      const smsMsg = `Lapis Suites STK Push Auth OTP: ${otpCode}. Confirm you are sending an M-Pesa prompt of KES ${amount.toLocaleString()} to ${tenantName}${unitNumber ? ` (Unit ${unitNumber})` : ''}. Valid 5 mins.`
      const smsRes = await sendSms({
        phone: adminPhone,
        message: smsMsg,
        purpose: 'admin_stk_otp',
        recipientEmail: adminEmail,
        userId: adminDoc?.id,
        meta: { amount, unitNumber, tenantName }
      })

      if (!smsRes.ok) {
        return res.status(502).json({ error: smsRes.error || 'Failed to send admin confirmation OTP via SMS.' })
      }

      await db.collection('admin_stk_otps').insertOne({
        challengeId,
        adminEmail,
        adminId: adminDoc?.id || req.user?.userId,
        otpHash,
        attempts: 0,
        used: false,
        expiresAt,
        createdAt: new Date().toISOString()
      })

      const challengeToken = jwt.sign(
        { purpose: 'admin_stk_otp', challengeId, adminEmail },
        JWT_SECRET,
        { expiresIn: '5m' }
      )

      const maskedPhone = maskKenyanPhone(adminPhone)
      logServerEvent('KCB-STK', `Dispatched Admin STK confirmation OTP to ${maskedPhone} for ${adminEmail}`)

      res.json({
        ok: true,
        challengeToken,
        maskedPhone,
        expiresInSeconds: 300,
        message: `Confirmation OTP sent via SMS to your admin number (${maskedPhone}).`
      })
    } catch (err: any) {
      res.status(500).json({ error: err.message || 'Failed to send admin STK confirmation OTP.' })
    }
  }
)

// 1c. Admin STK Push Step 2: Verify Admin SMS OTP & dispatch STK Push to resident
router.post(
  '/kcb/admin-stk/verify-and-push',
  authenticateToken,
  requireRole(['landlord']),
  createRateLimiter(10, 60000),
  async (req: AuthRequest, res: Response) => {
    try {
      const db = getDb()
      const { challengeToken, code, phoneNumber, amount, invoiceNumber, description, callerName, callerEmail, tenantId, unitNumber } = req.body

      if (!challengeToken || !code) {
        return res.status(400).json({ error: 'Admin OTP confirmation is required before sending an STK Push.' })
      }

      let decoded: any
      try {
        decoded = jwt.verify(String(challengeToken), JWT_SECRET)
      } catch {
        return res.status(401).json({ error: 'Admin OTP session expired. Please request a fresh confirmation code.' })
      }

      if (decoded.purpose !== 'admin_stk_otp' || decoded.adminEmail !== (req.user?.email || '').toLowerCase()) {
        return res.status(403).json({ error: 'Invalid admin OTP session.' })
      }

      const otpDoc = await db.collection('admin_stk_otps').findOne({ challengeId: decoded.challengeId })
      if (!otpDoc || otpDoc.used) {
        return res.status(400).json({ error: 'This confirmation OTP has already been used. Request a new code.' })
      }
      if (new Date(otpDoc.expiresAt).getTime() < Date.now()) {
        return res.status(400).json({ error: 'Confirmation OTP expired. Please request a new code.' })
      }
      if (Number(otpDoc.attempts || 0) >= 5) {
        return res.status(429).json({ error: 'Too many invalid OTP attempts. Request a new confirmation code.' })
      }

      const cleanCode = String(code).replace(/\D/g, '').trim()
      const expectedHash = crypto.createHash('sha256').update(`admin-stk:${cleanCode}:${JWT_SECRET}`).digest('hex')
      if (cleanCode.length !== 6 || expectedHash !== otpDoc.otpHash) {
        await db.collection('admin_stk_otps').updateOne({ challengeId: otpDoc.challengeId }, { $inc: { attempts: 1 } })
        return res.status(400).json({ error: 'Invalid 6-digit admin confirmation OTP. Please check your SMS and try again.' })
      }

      await db.collection('admin_stk_otps').updateOne(
        { challengeId: otpDoc.challengeId },
        { $set: { used: true, verifiedAt: new Date().toISOString() } }
      )

      logServerEvent('KCB-STK', `Admin OTP verified for ${req.user?.email}. Dispatching STK Push to ${phoneNumber}...`)
      const result = await initiateKcbStkPushCore({
        phoneNumber,
        amount: Number(amount),
        invoiceNumber,
        description,
        callerName: callerName || req.user?.name || 'Administrator',
        callerEmail: callerEmail || req.user?.email || 'admin@lapissuites.com',
        callerRole: 'landlord_otp_verified',
        callerIp: getClientIp(req),
        tenantId,
        unitNumber
      })

      res.json(result)
    } catch (err: any) {
      logServerEvent('KCB-STK', `Admin verified STK Push failed: ${err.message}`)
      res.status(err.status || 500).json({ error: err.message || 'Failed to execute STK Push.' })
    }
  }
)

/**
 * Shared idempotent reconciliation helper used by:
 * 1. KCB IPN Callback (/api/kcb/callback)
 * 2. Live KCB Status Sync (/api/kcb/query when a callback was missed while server was down)
 * 3. Admin manual resolution with M-Pesa receipt (/api/kcb/resolve-pending)
 */
async function finalizeSuccessfulKcbPayment(params: {
  kcbTx: any
  checkoutRequestId?: string
  merchantRequestId?: string
  mpesaReceiptNumber: string
  amount: number
  phoneNumber: string
  resultDesc?: string
  rawPayload?: any
  sourceLabel?: string
}) {
  const db = getDb()
  const nowIso = new Date().toISOString()
  const kcbTx = params.kcbTx
  const amount = Math.round(Number(params.amount || kcbTx?.amount || 0))
  const normalizedPhone = normalizeKenyanPhone(params.phoneNumber || kcbTx?.phoneNumber || '')

  let tenant: any = null
  if (normalizedPhone) {
    tenant = await db.collection('tenants').findOne({
      $or: [
        { phone: normalizedPhone },
        { phone: `+${normalizedPhone}` },
        { phone: `0${normalizedPhone.slice(3)}` }
      ]
    })
  }
  if (!tenant && kcbTx?.tenantId) {
    tenant = await db.collection('tenants').findOne({ id: kcbTx.tenantId })
  }
  if (!tenant && kcbTx?.unitNumber) {
    tenant = await db.collection('tenants').findOne({ currentUnitNumber: kcbTx.unitNumber })
  }
  if (!tenant && kcbTx?.unitNumber) {
    const l = await db.collection('leases').findOne({ unitNumber: kcbTx.unitNumber })
    if (l) tenant = await db.collection('tenants').findOne({ id: l.tenantId })
  }

  const lease = tenant ? await db.collection('leases').findOne({
    tenantId: tenant.id,
    status: { $in: ['active', 'pending_deposit'] }
  }) : null

  const unitNumber = tenant?.currentUnitNumber || lease?.unitNumber || kcbTx?.unitNumber || ''
  const unitId = tenant?.currentUnitId || lease?.unitId || null
  const leaseId = tenant?.currentLeaseId || lease?.id || null
  const tenantName = tenant?.name || kcbTx?.callerName || 'Resident'
  const ref = (params.mpesaReceiptNumber || `KCB${Date.now().toString().slice(-6)}`).trim().toUpperCase()
  const txDate = nowIso.slice(0, 10)

  let ledgerTx = await db.collection('transactions').findOne({ reference: ref })
  let updatedLease = lease
  let recSummary: any = null

  if (!ledgerTx && amount > 0) {
    ledgerTx = {
      id: generateHexObjectId(),
      reference: ref,
      invoiceRef: kcbTx?.invoiceNumber || `INV-KCB-${unitNumber || 'RENT'}`,
      tenantId: tenant?.id || null,
      tenantName,
      unitId,
      unitNumber,
      leaseId,
      amount,
      date: txDate,
      timestamp: nowIso.replace('T', ' ').slice(0, 19),
      method: 'stk_push',
      source: params.sourceLabel || 'callback',
      paymentType: 'deposit_and_rent',
      status: 'reconciled',
      category: 'rent',
      phoneNumber: normalizedPhone,
      payerName: tenantName,
      billRefNumber: unitNumber,
      notes: `KCB M-Pesa STK payment (${ref}) - Reconciled.`,
      reconciled: true,
      reconciledAt: nowIso,
      reconciledBy: params.sourceLabel === 'live_query' ? 'KCB Status Sync Engine' : 'Automated KCB IPN Webhook Engine',
      rawCallback: params.rawPayload || null
    } as any

    await db.collection('transactions').insertOne(ledgerTx as any)
    logServerEvent('PAYMENT', `Ledger updated (${params.sourceLabel || 'callback'}): Reconciled KES ${amount.toLocaleString()} for Unit ${unitNumber} (${tenantName}) [Ref: ${ref}]`)

    if (tenant?.id) {
      try {
        const recResult = await runTenantLedgerReconciliation(tenant.id)
        if (recResult.lease) updatedLease = recResult.lease
        recSummary = recResult.summary
      } catch (err: any) {
        logServerEvent('RECONCILE', `Auto reconciliation notice: ${err.message}`)
      }
    }

    // Update persistent payment link (keeps same linkId active on partial payments; marks 'paid' only when balance === 0)
    await recordPaymentAgainstActiveLink({
      tenantId: tenant?.id || null,
      paymentLinkId: kcbTx?.paymentLinkId || null,
      amount,
      mpesaReceipt: ref,
      transactionId: ledgerTx!.id,
      checkoutRequestId: params.checkoutRequestId || kcbTx?.checkoutRequestId || null,
      remainingBalance: Number(recSummary?.balance ?? 0)
    })

    const notifResident = {
      id: generateHexObjectId(),
      userId: tenant?.id || null,
      tenantId: tenant?.id || null,
      role: 'tenant',
      type: 'payment_received',
      title: `Payment Received (KES ${amount.toLocaleString()})`,
      message: `Your M-Pesa payment ${ref} of KES ${amount.toLocaleString()} for Unit ${unitNumber} has been received and reconciled.`,
      timestamp: nowIso,
      read: false,
      link: '/tenant/payments'
    }

    const notifLandlord = {
      id: generateHexObjectId(),
      userId: null,
      role: 'landlord',
      type: 'payment_received',
      title: `Payment Reconciled (Unit ${unitNumber})`,
      message: `${tenantName} paid KES ${amount.toLocaleString()} via KCB M-Pesa (${ref}). Ledger updated.`,
      timestamp: nowIso,
      read: false,
      link: '/payments'
    }

    await db.collection('notifications').insertMany([notifResident, notifLandlord])

    let balanceSnippet = ''
    if (recSummary) {
      if (recSummary.balance > 0) {
        balanceSnippet = ` Remaining balance: KES ${Math.round(recSummary.balance).toLocaleString()}.`
      } else if (recSummary.accountCredit > 0) {
        balanceSnippet = ` Prepaid credit: KES ${Math.round(recSummary.accountCredit).toLocaleString()}.`
      } else {
        balanceSnippet = ' Account is settled.'
      }
    }

    const tenantSmsPhone = tenant?.phone || normalizedPhone
    if (tenantSmsPhone) {
      const firstName = String(tenantName || 'Resident').split(' ')[0]
      notifyTenantSms(
        tenantSmsPhone,
        `Hi ${firstName}, Lapis Suites received your M-Pesa payment of KES ${amount.toLocaleString()} for Unit ${unitNumber} (Ref: ${ref}).${balanceSnippet} Thank you!`,
        'payment_receipt',
        { recipientEmail: tenant?.email, userId: tenant?.id || undefined, meta: { transactionId: ledgerTx!.id, reference: ref, paymentLinkId: kcbTx?.paymentLinkId || null } }
      )
    }

    notifyAdminsSms(
      `Lapis Suites Payment Received: ${tenantName} (Unit ${unitNumber}) paid KES ${amount.toLocaleString()} via M-Pesa STK (Ref: ${ref}).${balanceSnippet}`,
      'payment_landlord_alert',
      { transactionId: ledgerTx!.id, reference: ref, unitNumber, paymentLinkId: kcbTx?.paymentLinkId || null }
    )

    broadcastServerEvent('payment_received', {
      transaction: ledgerTx,
      lease: updatedLease,
      checkoutRequestId: params.checkoutRequestId || kcbTx?.checkoutRequestId,
      merchantRequestId: params.merchantRequestId || kcbTx?.merchantRequestId,
      tenantId: tenant?.id,
      phoneNumber: normalizedPhone,
      auditRecord: kcbTx
    })
    broadcastServerEvent('notification', notifResident)
    broadcastServerEvent('notification', notifLandlord)
  }

  return { ledgerTx, updatedLease, recSummary, ref, tenantName, unitNumber, tenant }
}

/**
 * Queries KCB Buni live STK query endpoint gracefully when a callback was missed.
 */
async function queryKcbBuniLive(checkoutRequestId: string, merchantRequestId?: string): Promise<{
  reachable: boolean
  resolved: boolean
  status?: 'Success' | 'Failed' | 'Pending'
  resultCode?: number
  resultDesc?: string
  mpesaReceiptNumber?: string
  amount?: number
  raw?: any
}> {
  try {
    const token = await getKcbAccessToken()
    const endpoints = [
      `${KCB_CONFIG.baseUrl}/mm/api/request/1.0.0/stkquery`,
      `${KCB_CONFIG.baseUrl}/mm/api/request/1.0.0/query`
    ]

    for (const url of endpoints) {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'routeCode': KCB_CONFIG.defaultRouteCode || '207',
          'operation': 'STKQuery',
          'messageId': generateHexObjectId(),
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          checkoutRequestId,
          CheckoutRequestID: checkoutRequestId,
          merchantRequestId: merchantRequestId || undefined
        })
      })

      if (res.status === 404) continue

      const rawText = await res.text()
      let data: any = null
      try { data = rawText ? JSON.parse(rawText) : {} } catch { data = { raw: rawText } }
      logServerEvent('KCB-QUERY-LIVE', `KCB Live Query (${res.status}) for ${checkoutRequestId}: ${rawText.slice(0, 300)}`)

      const body = data?.response || data?.Body?.stkCallback || data
      const rawCode = body?.ResultCode ?? body?.resultCode ?? data?.header?.statusCode
      const resultDesc = String(body?.ResultDesc || body?.resultDesc || data?.header?.statusDescription || '').trim()
      const receipt = String(body?.MpesaReceiptNumber || body?.mpesaReceiptNumber || body?.ReceiptNumber || '').trim()
      const amountVal = Number(body?.Amount || body?.amount || 0)

      if (rawCode !== undefined && rawCode !== null && rawCode !== '') {
        const numCode = Number(rawCode)
        // Safaricom/KCB standard: 0 = Success, 4999/500.001.1001 = Still processing, others (1032, 1037, 1, 2001) = Failed
        if (numCode === 0 && (receipt || /success|processed successfully/i.test(resultDesc))) {
          return { reachable: true, resolved: true, status: 'Success', resultCode: 0, resultDesc: resultDesc || 'Confirmed via KCB live status check', mpesaReceiptNumber: receipt, amount: amountVal, raw: data }
        }
        if ([1032, 1037, 1, 17, 26, 2001, 1001, 1019, 1025].includes(numCode) || /cancel|timeout|insufficient|wrong pin|failed|expired|unable/i.test(resultDesc)) {
          return { reachable: true, resolved: true, status: 'Failed', resultCode: numCode, resultDesc: resultDesc || 'Transaction failed or cancelled', raw: data }
        }
      }

      return { reachable: true, resolved: false, status: 'Pending', resultDesc: resultDesc || 'Transaction still processing at M-Pesa.', raw: data }
    }

    return { reachable: false, resolved: false, status: 'Pending', resultDesc: 'Live status query endpoint unavailable on current KCB environment.' }
  } catch (err: any) {
    logServerEvent('KCB-QUERY-LIVE', `Live KCB status query skipped/failed gracefully: ${err.message}`)
    return { reachable: false, resolved: false, status: 'Pending', resultDesc: 'Could not reach KCB live query right now.' }
  }
}

function safeCompareSecret(a: string, b: string): boolean {
  const bufA = Buffer.from(a)
  const bufB = Buffer.from(b)
  if (bufA.length !== bufB.length) return false
  return crypto.timingSafeEqual(bufA, bufB)
}

function hasValidKcbWebhookSecret(req: Request): boolean {
  const configured = KCB_CONFIG.webhookSecret
  if (!configured) return false
  const candidates = [
    String(req.params?.secret || '').trim(),
    String(req.query?.token || req.query?.secret || '').trim(),
    String(req.headers['x-kcb-secret'] || '').trim(),
    String(req.headers['x-webhook-secret'] || '').trim()
  ].filter(Boolean)

  return candidates.some((c) => safeCompareSecret(c, configured))
}

function canAccessKcbRecord(req: AuthRequest, tx: any): boolean {
  if (req.user?.role === 'landlord') return true
  const callerTenantId = req.user?.tenantId || req.user?.userId || req.paySession?.tenantId || ''
  const callerPhone = normalizeKenyanPhone(req.user?.phone || req.paySession?.phone || '')
  const callerUnit = req.user?.unitNumber || req.paySession?.unitNumber || ''
  if (callerTenantId && tx.tenantId && tx.tenantId === callerTenantId) return true
  if (callerPhone && tx.phoneNumber && normalizeKenyanPhone(tx.phoneNumber).slice(-9) === callerPhone.slice(-9)) return true
  if (callerUnit && tx.unitNumber && tx.unitNumber === callerUnit) return true
  return false
}

// 2. Query STK Push Status (Authenticated user or verified public pay session — Checks MongoDB first, then KCB Buni live!)
router.post('/kcb/query', authenticateUserOrPaySession, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()

    const { checkoutRequestId, merchantRequestId, syncLive = true } = req.body
    if (!checkoutRequestId && !merchantRequestId) {
      return res.status(400).json({ error: 'checkoutRequestId or merchantRequestId is required.' })
    }

    const query: any = {}
    if (checkoutRequestId) query.checkoutRequestId = String(checkoutRequestId)
    if (merchantRequestId) query.merchantRequestId = String(merchantRequestId)

    let tx: any = await db.collection('kcb_transactions').findOne(query)
    if (!tx) {
      return res.status(404).json({ status: 'NotFound', description: 'Transaction record not found.' })
    }
    if (!canAccessKcbRecord(req, tx)) {
      return res.status(403).json({ error: 'Access denied to this transaction status.' })
    }

    let checkedLive = false
    let liveNote = ''

    // If still Pending (e.g. callback was missed when backend was down), query KCB live!
    if (tx.status === 'Pending' && syncLive && tx.checkoutRequestId) {
      checkedLive = true
      const live = await queryKcbBuniLive(tx.checkoutRequestId, tx.merchantRequestId)
      liveNote = live.resultDesc || ''

      if (live.resolved && live.status === 'Success') {
        const nowIso = new Date().toISOString()
        await db.collection('kcb_transactions').updateOne(
          { _id: tx._id },
          {
            $set: {
              status: 'Success',
              statusCode: '0',
              statusDescription: live.resultDesc || 'Confirmed via KCB Live Query',
              resultCode: 0,
              resultDesc: live.resultDesc || 'Confirmed via KCB Live Query',
              mpesaReceiptNumber: live.mpesaReceiptNumber || tx.mpesaReceiptNumber || undefined,
              amount: live.amount && live.amount > 0 ? live.amount : tx.amount,
              updatedAt: nowIso,
              rawQueryResponse: live.raw
            }
          }
        )
        tx = await db.collection('kcb_transactions').findOne({ _id: tx._id })
        await finalizeSuccessfulKcbPayment({
          kcbTx: tx,
          checkoutRequestId: tx.checkoutRequestId,
          merchantRequestId: tx.merchantRequestId,
          mpesaReceiptNumber: live.mpesaReceiptNumber || tx.mpesaReceiptNumber || `KCB${Date.now().toString().slice(-6)}`,
          amount: live.amount && live.amount > 0 ? live.amount : tx.amount,
          phoneNumber: tx.phoneNumber,
          resultDesc: live.resultDesc,
          rawPayload: live.raw,
          sourceLabel: 'live_query'
        })
        broadcastServerEvent('audit_updated', { record: tx })
      } else if (live.resolved && live.status === 'Failed') {
        const nowIso = new Date().toISOString()
        await db.collection('kcb_transactions').updateOne(
          { _id: tx._id },
          {
            $set: {
              status: 'Failed',
              statusCode: String(live.resultCode ?? 500),
              statusDescription: live.resultDesc || 'Failed / Cancelled',
              resultCode: live.resultCode ?? -1,
              resultDesc: live.resultDesc || 'Failed / Cancelled',
              updatedAt: nowIso,
              rawQueryResponse: live.raw
            }
          }
        )
        tx = await db.collection('kcb_transactions').findOne({ _id: tx._id })
        broadcastServerEvent('audit_updated', { record: tx })
      }
    }

    logServerEvent('KCB-QUERY', `Query status for ${tx.merchantRequestId || tx.checkoutRequestId} -> ${tx.status} (live=${checkedLive})`)
    res.json({
      status: tx.status,
      statusCode: tx.statusCode,
      statusDescription: tx.statusDescription,
      resultCode: tx.resultCode,
      resultDesc: tx.resultDesc,
      mpesaReceiptNumber: tx.mpesaReceiptNumber,
      amount: tx.amount,
      phoneNumber: tx.phoneNumber,
      checkedLive,
      liveNote
    })
  } catch (err: any) {
    logServerEvent('KCB-QUERY', `Error querying STK status: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

// 2b. Admin Resolve Stuck Pending STK Push (when callback was missed during downtime and KCB UAT query doesn't return final status)
router.post('/kcb/resolve-pending', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { id, checkoutRequestId, merchantRequestId, action, mpesaReceiptNumber, reason } = req.body
    if (!action || !['confirm', 'fail'].includes(action)) {
      return res.status(400).json({ error: 'Action must be "confirm" or "fail".' })
    }

    const filter: any = {}
    if (id) filter.id = id
    else if (checkoutRequestId) filter.checkoutRequestId = checkoutRequestId
    else if (merchantRequestId) filter.merchantRequestId = merchantRequestId
    else return res.status(400).json({ error: 'Transaction identifier is required.' })

    const tx: any = await db.collection('kcb_transactions').findOne(filter)
    if (!tx) return res.status(404).json({ error: 'Pending STK record not found.' })

    const nowIso = new Date().toISOString()

    if (action === 'confirm') {
      const cleanReceipt = String(mpesaReceiptNumber || '').trim().toUpperCase()
      if (!cleanReceipt) {
        return res.status(400).json({ error: 'Please enter the M-Pesa receipt code to confirm this payment.' })
      }
      await db.collection('kcb_transactions').updateOne(
        { _id: tx._id },
        {
          $set: {
            status: 'Success',
            statusCode: '0',
            statusDescription: `Confirmed manually by ${req.user?.email} (missed callback recovery)`,
            resultCode: 0,
            resultDesc: 'Confirmed via Missed Callback Recovery',
            mpesaReceiptNumber: cleanReceipt,
            updatedAt: nowIso
          }
        }
      )
      const updatedTx = await db.collection('kcb_transactions').findOne({ _id: tx._id })
      await finalizeSuccessfulKcbPayment({
        kcbTx: updatedTx,
        checkoutRequestId: updatedTx?.checkoutRequestId,
        merchantRequestId: updatedTx?.merchantRequestId,
        mpesaReceiptNumber: cleanReceipt,
        amount: updatedTx?.amount,
        phoneNumber: updatedTx?.phoneNumber,
        sourceLabel: 'manual_recovery'
      })
      broadcastServerEvent('audit_updated', { record: updatedTx })
      return res.json({ ok: true, status: 'Success', record: updatedTx })
    }

    // Mark as Failed / Expired
    const failReason = String(reason || 'Marked expired/failed after missed callback').trim()
    await db.collection('kcb_transactions').updateOne(
      { _id: tx._id },
      {
        $set: {
          status: 'Failed',
          statusCode: '1037',
          statusDescription: failReason,
          resultCode: 1037,
          resultDesc: failReason,
          updatedAt: nowIso
        }
      }
    )
    const updatedTx = await db.collection('kcb_transactions').findOne({ _id: tx._id })
    broadcastServerEvent('audit_updated', { record: updatedTx })
    res.json({ ok: true, status: 'Failed', record: updatedTx })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// 3. KCB / M-Pesa IPN Callback Webhook (Hardened with secret verification + orphan guard + amount check + live cross-verification)
router.post(['/kcb/callback', '/kcb/webhook', '/kcb/callback/:secret', '/kcb/webhook/:secret'], async (req: Request, res: Response) => {
  try {
    const db = getDb()

    const secretVerified = hasValidKcbWebhookSecret(req)
    if (KCB_CONFIG.strictCallbackAuth && !secretVerified) {
      logServerEvent('SECURITY', `Rejected KCB callback with missing/invalid webhook secret from IP ${getClientIp(req)}`)
      return res.status(401).json({ error: 'Unauthorized webhook callback.' })
    }

    let payload: any = req.body
    const rawString = typeof payload === 'string'
      ? payload
      : (Buffer.isBuffer(payload) ? payload.toString('utf-8') : JSON.stringify(payload || {}))

    if (typeof payload === 'string') {
      try {
        payload = JSON.parse(payload)
      } catch (parseErr) {
        logServerEvent('KCB-CALLBACK', `JSON.parse attempted on string body: ${parseErr}`)
      }
    } else if (Buffer.isBuffer(payload)) {
      try {
        payload = JSON.parse(payload.toString('utf-8'))
      } catch {
        payload = {}
      }
    }

    logServerEvent('KCB-CALLBACK', `Received IPN Callback:`, payload)

    const stk = payload?.Body?.stkCallback ||
                payload?.Body?.StkCallback ||
                payload?.stkCallback ||
                payload?.StkCallback ||
                payload

    let checkoutRequestId = stk?.CheckoutRequestID ||
                            stk?.CheckoutRequestId ||
                            stk?.checkoutRequestId ||
                            stk?.checkoutRequestID ||
                            payload?.CheckoutRequestID ||
                            payload?.checkoutRequestId

    if (!checkoutRequestId && typeof rawString === 'string') {
      const m = rawString.match(/"CheckoutRequestID"\s*:\s*"([^"]+)"/i)
      if (m) checkoutRequestId = m[1]
    }

    let merchantRequestId = stk?.MerchantRequestID ||
                            stk?.MerchantRequestId ||
                            stk?.merchantRequestId ||
                            stk?.merchantRequestID ||
                            payload?.MerchantRequestID ||
                            payload?.merchantRequestId

    if (!merchantRequestId && typeof rawString === 'string') {
      const m = rawString.match(/"MerchantRequestID"\s*:\s*"([^"]+)"/i)
      if (m) merchantRequestId = m[1]
    }

    let resultCode = Number(stk?.ResultCode ?? stk?.resultCode ?? payload?.ResultCode ?? -1)
    if (resultCode === -1 && typeof rawString === 'string') {
      const m = rawString.match(/"ResultCode"\s*:\s*(-?\d+)/i)
      if (m) resultCode = Number(m[1])
    }

    let resultDesc = stk?.ResultDesc || stk?.resultDesc || payload?.ResultDesc || ''
    if (!resultDesc && typeof rawString === 'string') {
      const m = rawString.match(/"ResultDesc"\s*:\s*"([^"]+)"/i)
      if (m) resultDesc = m[1]
    }
    if (!resultDesc) resultDesc = resultCode === 0 ? 'The service request is processed successfully.' : 'Processed'

    if (!checkoutRequestId && !merchantRequestId) {
      logServerEvent('KCB-CALLBACK', 'Callback rejected: missing transaction identifiers.')
      return res.status(400).json({ error: 'Missing transaction identifiers' })
    }

    let mpesaReceiptNumber = ''
    let amount = 0
    let phoneNumber = ''

    // Parse items from CallbackMetadata
    const items = stk?.CallbackMetadata?.Item ||
                  stk?.callbackMetadata?.Item ||
                  stk?.CallbackMetadata?.item ||
                  stk?.callbackMetadata?.item ||
                  []

    if (Array.isArray(items)) {
      for (const item of items) {
        const name = item.Name || item.name
        const val = item.Value !== undefined ? item.Value : item.value
        if (name === 'MpesaReceiptNumber') mpesaReceiptNumber = String(val || '')
        if (name === 'Amount') amount = Number(val || 0)
        if (name === 'PhoneNumber') phoneNumber = String(val || '')
      }
    }

    if (!mpesaReceiptNumber && typeof rawString === 'string') {
      const m = rawString.match(/"Name"\s*:\s*"MpesaReceiptNumber"[^}]*?"Value"\s*:\s*"([^"]+)"/i) ||
                rawString.match(/"MpesaReceiptNumber"[^}]*?"Value"\s*:\s*"([^"]+)"/i)
      if (m) mpesaReceiptNumber = m[1]
    }
    if (!amount && typeof rawString === 'string') {
      const m = rawString.match(/"Name"\s*:\s*"Amount"[^}]*?"Value"\s*:\s*(\d+(\.\d+)?)/i) ||
                rawString.match(/"Amount"[^}]*?"Value"\s*:\s*(\d+(\.\d+)?)/i)
      if (m) amount = Number(m[1])
    }
    if (!phoneNumber && typeof rawString === 'string') {
      const m = rawString.match(/"Name"\s*:\s*"PhoneNumber"[^}]*?"Value"\s*:\s*"?(\d+)"?/i) ||
                rawString.match(/"PhoneNumber"[^}]*?"Value"\s*:\s*"?(\d+)"?/i)
      if (m) phoneNumber = String(m[1])
    }

    const isSuccess = resultCode === 0
    const newStatus = isSuccess ? 'Success' : 'Failed'
    const nowIso = new Date().toISOString()

    // 1. Prioritize matching kcb_transactions by exact request IDs first
    let kcbTx: any = null
    const idQueries: any[] = []
    if (checkoutRequestId) idQueries.push({ checkoutRequestId })
    if (merchantRequestId) idQueries.push({ merchantRequestId })

    if (idQueries.length > 0) {
      kcbTx = await db.collection('kcb_transactions').findOne({ $or: idQueries })
    }

    // Security Guard 1: Reject orphan / unsolicited callbacks that do not match any initiated STK transaction
    if (!kcbTx) {
      logServerEvent('SECURITY', `Rejected orphan KCB callback (no matching initiated STK record): checkoutRequestId=${checkoutRequestId || 'none'} merchantRequestId=${merchantRequestId || 'none'} from IP ${getClientIp(req)}`)
      return res.status(404).json({ ResultCode: 1, ResultDesc: 'Unknown transaction reference.' })
    }

    // Security Guard 2: If callback claims Success without verified webhook secret, cross-verify live with KCB Buni when reachable
    let spoofBlocked = false
    if (isSuccess && !secretVerified && kcbTx.checkoutRequestId) {
      const liveCheck = await queryKcbBuniLive(kcbTx.checkoutRequestId, kcbTx.merchantRequestId)
      if (liveCheck.reachable && liveCheck.resolved && liveCheck.status === 'Failed') {
        spoofBlocked = true
        logServerEvent('SECURITY', `BLOCKED SPOOFED KCB CALLBACK: Callback claimed Success for ${kcbTx.checkoutRequestId} from IP ${getClientIp(req)}, but KCB live query returned Failed (${liveCheck.resultDesc}).`)
        return res.status(403).json({ ResultCode: 1, ResultDesc: 'Callback verification failed.' })
      }
    }

    // Security Guard 3: Amount integrity check (flag significant mismatch instead of blind auto-credit)
    const expectedAmount = Number(kcbTx.amount || 0)
    const effectiveAmount = amount > 0 ? amount : expectedAmount
    const amountMismatch = isSuccess && expectedAmount > 0 && Math.abs(effectiveAmount - expectedAmount) > 1
    if (amountMismatch) {
      logServerEvent('SECURITY', `KCB callback amount mismatch for ${kcbTx.checkoutRequestId}: expected KES ${expectedAmount}, callback reported KES ${effectiveAmount}. Holding for manual verification.`)
    }

    // 3. Update the matched record (do not downgrade an already Success record)
    if (kcbTx.status !== 'Success' && !spoofBlocked) {
      await db.collection('kcb_transactions').updateOne(
        { _id: kcbTx._id },
        {
          $set: {
            checkoutRequestId: checkoutRequestId || kcbTx.checkoutRequestId,
            merchantRequestId: merchantRequestId || kcbTx.merchantRequestId,
            status: amountMismatch ? 'Flagged' : newStatus,
            statusCode: isSuccess && !amountMismatch ? '0' : '500',
            statusDescription: amountMismatch ? `Amount mismatch (expected KES ${expectedAmount}, received KES ${effectiveAmount})` : resultDesc,
            resultCode,
            resultDesc,
            mpesaReceiptNumber: mpesaReceiptNumber || kcbTx.mpesaReceiptNumber,
            amount: effectiveAmount,
            webhookSecretVerified: secretVerified,
            updatedAt: nowIso,
            rawCallback: payload
          }
        }
      )
      kcbTx = await db.collection('kcb_transactions').findOne({ _id: kcbTx._id })
    }

    logServerEvent('KCB-CALLBACK', `Transaction updated: ${merchantRequestId || checkoutRequestId} -> ${newStatus} (${resultDesc}) [M-Pesa: ${mpesaReceiptNumber || 'N/A'}]`)

    // Notify any waiting clients via EventEmitter immediately
    const callbackEvent = {
      checkoutRequestId,
      merchantRequestId,
      status: newStatus,
      resultCode,
      resultDesc,
      mpesaReceiptNumber,
      amount,
      phoneNumber
    }
    if (checkoutRequestId) {
      callbackEmitter.emit(`callback:${checkoutRequestId}`, callbackEvent)
    }
    if (merchantRequestId) {
      callbackEmitter.emit(`callback:${merchantRequestId}`, callbackEvent)
    }

    let tenant: any = null
    let lease: any = null
    let unitNumber = '125F'
    let unitId: any = null
    let leaseId: any = null
    let tenantName = 'Resident'

    if (!kcbTx) {
      const fallbackQuery: any[] = []
      if (checkoutRequestId) fallbackQuery.push({ checkoutRequestId })
      if (merchantRequestId) fallbackQuery.push({ merchantRequestId })
      if (fallbackQuery.length > 0) {
        kcbTx = await db.collection('kcb_transactions').findOne({ $or: fallbackQuery })
      }
    }

    // Resolve tenant & unit
    const normalizedPhone = normalizeKenyanPhone(phoneNumber || kcbTx?.phoneNumber || '')
    tenant = await db.collection('tenants').findOne({
      $or: [
        { phone: normalizedPhone },
        { phone: `+${normalizedPhone}` },
        { phone: `0${normalizedPhone.slice(3)}` }
      ]
    })
    if (!tenant && kcbTx?.tenantId) {
      tenant = await db.collection('tenants').findOne({ id: kcbTx.tenantId })
    }
    if (!tenant && kcbTx?.unitNumber) {
      tenant = await db.collection('tenants').findOne({ currentUnitNumber: kcbTx.unitNumber })
    }
    if (!tenant) {
      const l = await db.collection('leases').findOne({ unitNumber: kcbTx?.unitNumber })
      if (l) {
        tenant = await db.collection('tenants').findOne({ id: l.tenantId })
      }
    }

    lease = tenant ? await db.collection('leases').findOne({
      tenantId: tenant.id,
      status: { $in: ['active', 'pending_deposit'] }
    }) : null

    unitNumber = tenant?.currentUnitNumber || lease?.unitNumber || kcbTx?.unitNumber || '125F'
    unitId = tenant?.currentUnitId || lease?.unitId || null
    leaseId = tenant?.currentLeaseId || lease?.id || null
    tenantName = tenant?.name || kcbTx?.callerName || 'Resident'
    const ref = mpesaReceiptNumber || `KCB${Date.now().toString().slice(-6)}`
    const txDate = nowIso.slice(0, 10)

    // 1. Always save the raw & parsed callback in kcb_callbacks
    const callbackDoc = {
      id: generateHexObjectId(),
      rawPayload: payload,
      rawString,
      receivedAt: nowIso,
      parsed: {
        checkoutRequestId,
        merchantRequestId,
        resultCode,
        resultDesc,
        isSuccess,
        mpesaReceiptNumber: mpesaReceiptNumber || undefined,
        amount,
        phoneNumber: normalizedPhone,
        transactionDate: nowIso.replace('T', ' ').slice(0, 19),
        matchedTenantId: tenant?.id || null,
        matchedTenantName: tenantName,
        matchedUnitNumber: unitNumber,
        matchedLeaseId: leaseId
      }
    }
    await db.collection('kcb_callbacks').insertOne(callbackDoc)

    let ledgerTx: any = null
    let updatedLease: any = lease

    // If successful and amount verified, automatically reconcile into ledger and notify resident and landlord
    if (isSuccess && !amountMismatch && effectiveAmount > 0) {
      // Prevent duplicate transaction entries
      const existingLedger = await db.collection('transactions').findOne({ reference: ref })
      if (!existingLedger) {
        ledgerTx = {
          id: generateHexObjectId(),
          reference: ref,
          invoiceRef: kcbTx?.invoiceNumber || `INV-KCB-${unitNumber}`,
          tenantId: tenant?.id || null,
          tenantName,
          unitId,
          unitNumber,
          leaseId,
          amount,
          date: txDate,
          timestamp: nowIso.replace('T', ' ').slice(0, 19),
          method: 'stk_push',
          source: 'callback',
          paymentType: 'deposit_and_rent',
          status: 'reconciled',
          category: 'rent',
          phoneNumber: normalizedPhone,
          payerName: tenantName,
          billRefNumber: unitNumber,
          notes: `KCB M-Pesa STK payment (${ref}) - Reconciled automatically.`,
          reconciled: true,
          reconciledAt: nowIso,
          reconciledBy: 'Automated KCB IPN Webhook Engine',
          rawCallback: payload
        }

        await db.collection('transactions').insertOne(ledgerTx)
        logServerEvent('PAYMENT', `Ledger updated: Reconciled KES ${amount.toLocaleString()} for Unit ${unitNumber} (${tenantName}) [Ref: ${ref}]`)

        // Run full ledger & deposit reconciliation for this tenant
        let recSummary: any = null
        if (tenant?.id) {
          try {
            const recResult = await runTenantLedgerReconciliation(tenant.id)
            if (recResult.lease) updatedLease = recResult.lease
            recSummary = recResult.summary
          } catch (err: any) {
            logServerEvent('RECONCILE', `Auto reconciliation on callback: ${err.message}`)
          }
        }

        // Update persistent payment link: keeps the same linkId active on partial payments,
        // and only marks 'paid' once the tenant's full balance reaches 0!
        const paymentLinkId = kcbTx?.paymentLinkId || null
        await recordPaymentAgainstActiveLink({
          tenantId: tenant?.id || null,
          paymentLinkId,
          amount,
          mpesaReceipt: ref,
          transactionId: ledgerTx.id,
          checkoutRequestId: checkoutRequestId || kcbTx?.checkoutRequestId || null,
          remainingBalance: Number(recSummary?.balance ?? 0)
        })

        // Create in-app notifications
        const notifResident = {
          id: generateHexObjectId(),
          userId: tenant?.id || null,
          tenantId: tenant?.id || null,
          role: 'tenant',
          type: 'payment_received',
          title: `Payment Received (KES ${amount.toLocaleString()})`,
          message: `Your M-Pesa payment ${ref} of KES ${amount.toLocaleString()} for Unit ${unitNumber} has been received and reconciled.`,
          timestamp: nowIso,
          read: false,
          link: '/tenant/payments'
        }

        const notifLandlord = {
          id: generateHexObjectId(),
          userId: null,
          role: 'landlord',
          type: 'payment_received',
          title: `Payment Reconciled (Unit ${unitNumber})`,
          message: `${tenantName} paid KES ${amount.toLocaleString()} via KCB M-Pesa (${ref}). Ledger updated.`,
          timestamp: nowIso,
          read: false,
          link: '/payments'
        }

        await db.collection('notifications').insertMany([notifResident, notifLandlord])
        logServerEvent('NOTIFICATION', `Dispatched payment notifications to resident and management for ${ref}`)

        // KCB Payment Callback: Inform BOTH the tenant AND the landlord(s) via SMS
        let balanceSnippet = ''
        if (recSummary) {
          if (recSummary.balance > 0) {
            balanceSnippet = ` Remaining balance: KES ${Math.round(recSummary.balance).toLocaleString()}.`
          } else if (recSummary.accountCredit > 0) {
            balanceSnippet = ` Prepaid credit: KES ${Math.round(recSummary.accountCredit).toLocaleString()}.`
          } else {
            balanceSnippet = ' Account is settled.'
          }
        }

        const tenantSmsPhone = tenant?.phone || normalizedPhone
        if (tenantSmsPhone) {
          const firstName = String(tenantName || 'Resident').split(' ')[0]
          notifyTenantSms(
            tenantSmsPhone,
            `Hi ${firstName}, Lapis Suites received your M-Pesa payment of KES ${amount.toLocaleString()} for Unit ${unitNumber} (Ref: ${ref}).${balanceSnippet} Thank you!`,
            'payment_receipt',
            {
              recipientEmail: tenant?.email,
              userId: tenant?.id || undefined,
              meta: { transactionId: ledgerTx.id, reference: ref, paymentLinkId }
            }
          )
        }

        notifyAdminsSms(
          `Lapis Suites Payment Received: ${tenantName} (Unit ${unitNumber}) paid KES ${amount.toLocaleString()} via M-Pesa STK (Ref: ${ref}).${balanceSnippet}`,
          'payment_landlord_alert',
          { transactionId: ledgerTx.id, reference: ref, unitNumber, paymentLinkId }
        )

        // Broadcast realtime SSE events to all connected clients
        broadcastServerEvent('payment_received', {
          transaction: ledgerTx,
          lease: updatedLease,
          checkoutRequestId,
          merchantRequestId,
          tenantId: tenant?.id,
          phoneNumber: normalizedPhone,
          auditRecord: kcbTx
        })
        broadcastServerEvent('kcb_callback', {
          callback: callbackDoc,
          transaction: ledgerTx,
          auditRecord: kcbTx
        })
        broadcastServerEvent('audit_updated', {
          record: kcbTx
        })
        broadcastServerEvent('notification', notifResident)
        broadcastServerEvent('notification', notifLandlord)
      } else {
        ledgerTx = existingLedger
      }
    } else {
      // Broadcast failed callback event so waiting UI can update instantly
      broadcastServerEvent('kcb_callback', {
        callback: callbackDoc,
        checkoutRequestId,
        merchantRequestId,
        status: newStatus,
        resultDesc,
        auditRecord: kcbTx
      })
      broadcastServerEvent('audit_updated', {
        record: kcbTx
      })
    }

    res.json({ ResultCode: 0, ResultDesc: 'Accepted' })
  } catch (err: any) {
    logServerEvent('KCB-CALLBACK', `Error handling callback: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

// 3b. Wait for STK Callback (Authenticated user or verified public pay session — Efficient single event-driven wait)
router.post('/kcb/wait-callback', authenticateUserOrPaySession, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()

    const { checkoutRequestId, merchantRequestId, timeout = 50000 } = req.body
    if (!checkoutRequestId && !merchantRequestId) {
      return res.status(400).json({ error: 'checkoutRequestId or merchantRequestId is required.' })
    }

    const query: any = {}
    if (checkoutRequestId) query.checkoutRequestId = String(checkoutRequestId)
    if (merchantRequestId) query.merchantRequestId = String(merchantRequestId)

    // 1. Check if the callback already arrived and completed + verify ownership
    const existing = await db.collection('kcb_transactions').findOne(query)
    if (existing && !canAccessKcbRecord(req, existing)) {
      return res.status(403).json({ error: 'Access denied to this transaction.' })
    }
    if (existing && existing.status !== 'Pending') {
      return res.json({
        status: existing.status,
        statusCode: existing.statusCode,
        statusDescription: existing.statusDescription,
        resultCode: existing.resultCode,
        resultDesc: existing.resultDesc,
        mpesaReceiptNumber: existing.mpesaReceiptNumber,
        amount: existing.amount,
        phoneNumber: existing.phoneNumber
      })
    }

    // 2. Wait for callback event with a clean single timeout
    let finished = false
    const cleanup = () => {
      finished = true
      if (checkoutRequestId) callbackEmitter.removeListener(`callback:${checkoutRequestId}`, onCallback)
      if (merchantRequestId) callbackEmitter.removeListener(`callback:${merchantRequestId}`, onCallback)
      if (timer) clearTimeout(timer)
    }

    const onCallback = (data: any) => {
      if (finished) return
      cleanup()
      res.json(data)
    }

    if (checkoutRequestId) callbackEmitter.once(`callback:${checkoutRequestId}`, onCallback)
    if (merchantRequestId) callbackEmitter.once(`callback:${merchantRequestId}`, onCallback)

    const waitMs = Math.min(Math.max(Number(timeout) || 50000, 5000), 75000)
    const timer = setTimeout(async () => {
      if (finished) return
      cleanup()

      // Final DB check on timeout
      const latest = await db.collection('kcb_transactions').findOne(query)
      res.json({
        status: latest?.status || 'Pending',
        statusCode: latest?.statusCode || '0',
        statusDescription: latest?.statusDescription || 'Awaiting M-Pesa callback. You can check manually.',
        resultCode: latest?.resultCode,
        resultDesc: latest?.resultDesc,
        mpesaReceiptNumber: latest?.mpesaReceiptNumber,
        amount: latest?.amount,
        phoneNumber: latest?.phoneNumber
      })
    }, waitMs)

    req.on('close', () => {
      if (!finished) {
        cleanup()
      }
    })
  } catch (err: any) {
    logServerEvent('KCB-WAIT', `Error waiting for callback: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

// 4. Admin KCB Audit Logs (Protected for Landlord)
router.get('/kcb/audit-logs', authenticateToken, requireRole(['landlord']), async (_req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const records = await db.collection('kcb_transactions')
      .find({}, { projection: { _id: 0 } })
      .sort({ createdAt: -1 })
      .limit(100)
      .toArray()

    logServerEvent('AUDIT', `Served ${records.length} KCB transaction audit records to admin`)
    res.json(records)
  } catch (err: any) {
    logServerEvent('AUDIT', `Error retrieving audit records: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

// 5. Get Saved IPN Callbacks (Landlord only — Parsed & Raw for Reconciliation View)
router.get('/kcb/callbacks', authenticateToken, requireRole(['landlord']), async (_req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const callbacks = await db.collection('kcb_callbacks')
      .find({}, { projection: { _id: 0 } })
      .sort({ receivedAt: -1 })
      .limit(100)
      .toArray()
    res.json(callbacks)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
