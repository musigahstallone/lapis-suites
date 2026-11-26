import { Router, Response } from 'express'
import { getDb } from '../db'
import { generateHexObjectId } from '../config'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { logServerEvent } from '../middleware/logger'
import { broadcastServerEvent } from '../events'
import { notifyTenantSms, sendBulkSms } from '../services/sms'

const router = Router()

// GET /api/notifications
router.get('/notifications', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    let query: any = {}
    if (user.role === 'tenant') {
      const tenantOrClauses: any[] = [
        { role: 'all', tenantId: { $exists: false } },
        { role: 'all', tenantId: null },
        { role: 'tenant', tenantId: { $exists: false } },
        { role: 'tenant', tenantId: null }
      ]
      if (user.tenantId) tenantOrClauses.push({ tenantId: user.tenantId })
      if (user.userId) {
        tenantOrClauses.push({ tenantId: user.userId })
        tenantOrClauses.push({ userId: user.userId })
      }
      query = { $or: tenantOrClauses }
    } else {
      query = { $or: [{ role: 'landlord' }, { role: 'all' }] }
    }

    const notifications = await db.collection('notifications')
      .find(query, { projection: { _id: 0 } })
      .sort({ timestamp: -1 })
      .limit(30)
      .toArray()

    res.json(notifications)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/notifications/:id/read
router.post('/notifications/:id/read', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { id } = req.params
    await db.collection('notifications').updateOne({ id }, { $set: { read: true } })
    res.json({ success: true })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/notifications/mark-all-read
router.post('/notifications/mark-all-read', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    let query: any = {}
    if (user.role === 'tenant') {
      query = { $or: [{ tenantId: user.tenantId }, { role: 'tenant' }, { role: 'all' }] }
    } else {
      query = { $or: [{ role: 'landlord' }, { role: 'all' }] }
    }
    await db.collection('notifications').updateMany(query, { $set: { read: true } })
    logServerEvent('NOTIFICATION', `Marked all notifications as read for ${user.email}`)
    res.json({ success: true })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/notifications/broadcast
// Landlord sends an in-app + optional SMS notification to a single tenant or all active tenants
router.post('/notifications/broadcast', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { title, message, tenantId, sendSms: shouldSendSms = true } = req.body
    if (!title || !message) {
      return res.status(400).json({ error: 'Title and message are required.' })
    }

    const nowIso = new Date().toISOString()
    const cleanTitle = String(title).trim()
    const cleanMessage = String(message).trim()

    if (tenantId) {
      const tenant = await db.collection('tenants').findOne({ id: tenantId })
      if (!tenant) return res.status(404).json({ error: 'Tenant not found.' })

      const notif = {
        id: generateHexObjectId(),
        tenantId: tenant.id,
        role: 'tenant',
        type: 'announcement',
        title: cleanTitle,
        message: cleanMessage,
        timestamp: nowIso,
        read: false,
        link: '/tenant/home'
      }
      await db.collection('notifications').insertOne(notif)
      broadcastServerEvent('notification', notif)

      let smsRes = null
      if (shouldSendSms && tenant.phone) {
        const firstName = String(tenant.name || 'Resident').split(' ')[0]
        smsRes = await notifyTenantSms(
          tenant.phone,
          `Lapis Suites (${cleanTitle}): Hi ${firstName}, ${cleanMessage}`,
          'notification',
          { recipientEmail: tenant.email, userId: tenant.id }
        )
      }

      return res.status(201).json({ ok: true, sentCount: 1, sms: smsRes })
    }

    // Broadcast to all active tenants
    const tenants = await db.collection('tenants').find({ status: { $ne: 'inactive' } }).toArray()
    const notif = {
      id: generateHexObjectId(),
      role: 'tenant',
      type: 'announcement',
      title: cleanTitle,
      message: cleanMessage,
      timestamp: nowIso,
      read: false,
      link: '/tenant/home'
    }
    await db.collection('notifications').insertOne(notif)
    broadcastServerEvent('notification', notif)

    let bulkRes = null
    if (shouldSendSms) {
      const recipients = tenants
        .filter((t: any) => Boolean(t.phone))
        .map((t: any) => ({
          phone: t.phone,
          message: `Lapis Suites (${cleanTitle}): Hi ${String(t.name || 'Resident').split(' ')[0]}, ${cleanMessage}`
        }))
      if (recipients.length > 0) {
        bulkRes = await sendBulkSms({ recipients, purpose: 'announcement' })
      }
    }

    logServerEvent('NOTIFICATION', `Broadcasted notice "${cleanTitle}" to ${tenants.length} tenants (SMS: ${shouldSendSms})`)
    res.status(201).json({ ok: true, sentCount: tenants.length, sms: bulkRes })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
