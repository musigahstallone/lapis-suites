import crypto from 'crypto'
import { Router, Request, Response } from 'express'
import { getDb, isDbConnected } from '../db'
import { MOBILESASA_CONFIG, generateHexObjectId } from '../config'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { logServerEvent } from '../middleware/logger'

const router = Router()

function safeCompare(a: string, b: string): boolean {
  const bufA = Buffer.from(a)
  const bufB = Buffer.from(b)
  if (bufA.length !== bufB.length) return false
  return crypto.timingSafeEqual(bufA, bufB)
}

function verifyMobileSasaWebhook(req: Request): boolean {
  const configuredSecret = MOBILESASA_CONFIG.webhookSecret
  if (!configuredSecret) {
    // If no webhook secret is configured yet, accept callbacks while logging a reminder
    return true
  }

  const headerSecret = String(req.headers['x-mobilesasa-secret'] || '').trim()
  if (headerSecret && safeCompare(headerSecret, configuredSecret)) {
    return true
  }

  const headerSignature = String(req.headers['x-mobilesasa-signature'] || '').trim()
  const rawBody: string = (req as any).rawBody || JSON.stringify(req.body || {})
  if (headerSignature) {
    const cleanSig = headerSignature.replace(/^sha256=/i, '')
    const expectedHex = crypto.createHmac('sha256', configuredSecret).update(rawBody).digest('hex')
    const expectedBase64 = crypto.createHmac('sha256', configuredSecret).update(rawBody).digest('base64')
    if (safeCompare(cleanSig, expectedHex) || safeCompare(cleanSig, expectedBase64)) {
      return true
    }
  }

  return false
}

/**
 * POST /api/sms/dlr
 * Receives MobileSasa Delivery Report (DLR) webhooks.
 * Responds 200 quickly (<5s), deduplicates at-least-once callbacks on reference + status,
 * and updates the matching MongoDB `sms_logs` record.
 */
router.post('/sms/dlr', async (req: Request, res: Response) => {
  if (!verifyMobileSasaWebhook(req)) {
    logServerEvent('SMS-DLR', 'Rejected webhook: invalid X-MobileSasa-Secret / X-MobileSasa-Signature')
    return res.status(401).json({ ok: false, error: 'Unauthorized webhook signature.' })
  }

  const payload = req.body || {}
  const reference = String(payload.reference || '').trim()
  const trackingId = String(payload.trackingId || payload.dlr?.tracking_id || '').trim()
  const status = String(payload.status || '').trim()
  const deliveryStatus = String(payload.deliveryStatus || payload.dlr?.description || '').trim()
  const deliveryTime = String(payload.deliveryTime || payload.dlr?.delivered_at || '').trim()
  const msisdn = String(payload.msisdn || payload.dlr?.msisdn || '').trim()
  const costKes = payload.cost !== undefined && payload.cost !== null ? String(payload.cost) : null
  const sender = String(payload.sender || '').trim()
  const gateway = String(payload.dlr?.gateway || '').trim()
  const deliveryCode = payload.dlr?.delivery_code !== undefined ? String(payload.dlr.delivery_code) : ''
  const isFromSandBox = Boolean(payload.isFromSandBox)

  if (!reference && !trackingId) {
    return res.status(400).json({ ok: false, error: 'Invalid DLR payload: missing reference and trackingId.' })
  }

  // Acknowledge immediately to meet MobileSasa's <5s webhook hygiene requirement
  res.status(200).json({ ok: true, received: true })

  // Process persistence asynchronously
  setImmediate(async () => {
    try {
      if (!isDbConnected()) return
      const db = getDb()
      const nowIso = new Date().toISOString()

      const matchCriteria: any[] = []
      if (trackingId) matchCriteria.push({ trackingId })
      if (reference) {
        matchCriteria.push({ messageId: reference })
        matchCriteria.push({ bulkId: reference })
      }

      const existing = await db.collection('sms_logs').findOne({ $or: matchCriteria })

      const eventEntry = {
        reference,
        trackingId: trackingId || null,
        status: status || 'Unknown',
        deliveryStatus: deliveryStatus || null,
        deliveryTime: deliveryTime || null,
        gateway: gateway || null,
        deliveryCode,
        msisdn: msisdn || null,
        costKes,
        isFromSandBox,
        receivedAt: nowIso
      }

      if (existing) {
        // Deduplicate on reference + status
        const alreadyRecorded = Array.isArray(existing.dlrHistory) && existing.dlrHistory.some(
          (entry: any) => entry.reference === reference && entry.status === eventEntry.status && entry.msisdn === eventEntry.msisdn
        )
        if (alreadyRecorded) {
          logServerEvent('SMS-DLR', `Duplicate DLR ignored (${reference} -> ${status})`)
          return
        }

        await db.collection('sms_logs').updateOne(
          { _id: existing._id },
          {
            $set: {
              status: status || existing.status,
              deliveryStatus: deliveryStatus || existing.deliveryStatus,
              deliveryTime: deliveryTime || existing.deliveryTime,
              gateway: gateway || existing.gateway,
              deliveryCode,
              costKes: costKes ?? existing.costKes,
              isFromSandBox,
              updatedAt: nowIso
            },
            $push: { dlrHistory: eventEntry as any }
          }
        )
      } else {
        await db.collection('sms_logs').insertOne({
          id: generateHexObjectId(),
          type: 'dlr_orphan',
          trackingId: trackingId || reference,
          messageId: reference || null,
          phone: msisdn || null,
          senderId: sender || MOBILESASA_CONFIG.senderId,
          purpose: 'webhook_callback',
          status: status || 'Unknown',
          deliveryStatus: deliveryStatus || null,
          deliveryTime: deliveryTime || null,
          gateway: gateway || null,
          deliveryCode,
          costKes,
          isFromSandBox,
          dlrHistory: [eventEntry],
          createdAt: nowIso,
          updatedAt: nowIso
        })
      }

      logServerEvent('SMS-DLR', `Recorded DLR: ref=${reference || 'n/a'} trackingId=${trackingId || 'n/a'} status=${status} (${deliveryStatus || 'n/a'}) gateway=${gateway || 'n/a'}`)
    } catch (err: any) {
      logServerEvent('SMS-DLR', `Failed saving DLR callback: ${err.message}`)
    }
  })
})

/**
 * GET /api/sms/logs
 * Admin-only read access to recent SMS dispatches and delivery reports.
 */
router.get('/sms/logs', authenticateToken, requireRole(['landlord']), async (_req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const logs = await db.collection('sms_logs')
      .find({}, { projection: { _id: 0 } })
      .sort({ createdAt: -1 })
      .limit(100)
      .toArray()
    res.json(logs)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
