import { Router, Response } from 'express'
import { getDb } from '../db'
import { generateHexObjectId } from '../config'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { logServerEvent } from '../middleware/logger'
import { notifyAdminsSms, notifyTenantSms } from '../services/sms'
import { broadcastServerEvent } from '../events'

const router = Router()

// GET /api/maintenance - Filtered by role
router.get('/maintenance', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user
    let query: any = {}
    if (user && user.role === 'tenant') {
      const ids = [user.tenantId, user.userId].filter(Boolean)
      if (ids.length === 0) return res.json([])
      query = { tenantId: { $in: ids } }
    }
    const items = await db.collection('maintenance').find(query, { projection: { _id: 0 } }).sort({ createdAt: -1 }).toArray()

    logServerEvent('MAINTENANCE', `Served ${items.length} tickets to ${user?.email || 'Anonymous'} (${user?.role || 'none'})`)
    res.json(items)
  } catch (err: any) {
    logServerEvent('MAINTENANCE', `Error getting tickets: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

// POST /api/maintenance - Create new ticket (Supports BOTH Resident & Admin creation)
router.post('/maintenance', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    const { tenantId: reqTenantId, unitId, unitNumber, category, priority, title, description } = req.body

    if (!title || !description) {
      return res.status(400).json({ error: 'Title and description are required.' })
    }

    let resolvedTenantId = user.tenantId || user.userId
    let resolvedTenantName = user.name
    let resolvedUnitId = unitId || null
    let resolvedUnitNumber = unitNumber || user.unitNumber || ''
    let targetTenantDoc: any = null

    if (user.role === 'landlord') {
      if (reqTenantId) {
        targetTenantDoc = await db.collection('tenants').findOne({ id: reqTenantId })
      } else if (unitNumber) {
        targetTenantDoc = await db.collection('tenants').findOne({ currentUnitNumber: String(unitNumber).trim() })
      }
      if (targetTenantDoc) {
        resolvedTenantId = targetTenantDoc.id
        resolvedTenantName = targetTenantDoc.name
        resolvedUnitId = resolvedUnitId || targetTenantDoc.currentUnitId || null
        resolvedUnitNumber = resolvedUnitNumber || targetTenantDoc.currentUnitNumber || ''
      }
    }

    const nowIso = new Date().toISOString().replace('T', ' ').slice(0, 19)
    const newTicket = {
      id: generateHexObjectId(),
      tenantId: resolvedTenantId,
      tenantName: resolvedTenantName,
      unitId: resolvedUnitId,
      unitNumber: resolvedUnitNumber,
      category: category || 'general',
      priority: priority || 'medium',
      title: String(title).trim(),
      description: String(description).trim(),
      status: 'pending',
      createdByRole: user.role,
      createdAt: nowIso
    }

    await db.collection('maintenance').insertOne(newTicket)
    logServerEvent('MAINTENANCE', `New maintenance ticket created (${user.role}): "${newTicket.title}" for Unit ${newTicket.unitNumber}`)

    if (user.role === 'landlord') {
      // Admin created ticket: notify & SMS the resident!
      if (resolvedTenantId) {
        await db.collection('notifications').insertOne({
          id: generateHexObjectId(),
          userId: resolvedTenantId,
          tenantId: resolvedTenantId,
          role: 'tenant',
          type: 'maintenance_update',
          title: `Maintenance Logged: ${newTicket.title}`,
          message: `Property management logged a ${newTicket.category} maintenance ticket for Unit ${newTicket.unitNumber}: "${newTicket.title}".`,
          timestamp: new Date().toISOString(),
          read: false,
          link: '/tenant/maintenance'
        })
      }

      const tenantPhone = targetTenantDoc?.phone
      if (tenantPhone) {
        const firstName = String(resolvedTenantName || 'Resident').split(' ')[0]
        notifyTenantSms(
          tenantPhone,
          `Hi ${firstName}, Lapis Suites logged a maintenance ticket for Unit ${newTicket.unitNumber || 'your suite'}: "${newTicket.title}" (${newTicket.category}). We will keep you updated.`,
          'maintenance_update',
          { recipientEmail: targetTenantDoc?.email, userId: resolvedTenantId, meta: { ticketId: newTicket.id } }
        )
      }
    } else {
      // Resident created ticket: notify & SMS the landlord(s)!
      const notif = {
        id: generateHexObjectId(),
        userId: null,
        role: 'landlord',
        type: 'maintenance_update',
        title: `Maintenance Request: Unit ${newTicket.unitNumber}`,
        message: `${newTicket.tenantName} logged a ${newTicket.category} request: "${newTicket.title}" (${newTicket.priority.toUpperCase()})`,
        timestamp: new Date().toISOString(),
        read: false,
        link: '/maintenance'
      }
      await db.collection('notifications').insertOne(notif)

      notifyAdminsSms(
        `Lapis Suites Maintenance [${String(newTicket.priority).toUpperCase()}]: Unit ${newTicket.unitNumber || 'N/A'} (${newTicket.tenantName}) reported "${newTicket.title}" (${newTicket.category}).`,
        'maintenance_alert',
        { ticketId: newTicket.id, unitNumber: newTicket.unitNumber }
      )
    }

    res.status(201).json(newTicket)
  } catch (err: any) {
    logServerEvent('MAINTENANCE', `Error creating ticket: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

// PUT /api/maintenance/:id - Update status / assign technician (Landlord only)
// Rules:
//   1. Once status is 'resolved', ticket is LOCKED (cannot be edited or reopened).
//   2. SMS is ONLY sent on key lifecycle transitions: ticket created (POST), starting ('in_progress'), and done ('resolved').
router.put('/maintenance/:id', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const id = String(req.params.id)
    const { status, assignedTo, resolutionNotes } = req.body
    const nowIso = new Date().toISOString().replace('T', ' ').slice(0, 19)

    const existing = await db.collection('maintenance').findOne({ id })
    if (!existing) {
      return res.status(404).json({ error: 'Maintenance ticket not found.' })
    }

    if (String(existing.status || '').toLowerCase() === 'resolved') {
      return res.status(400).json({
        error: 'This maintenance ticket is already resolved and locked. Completed tickets cannot be edited or reopened.'
      })
    }

    const previousStatus = String(existing.status || 'pending').toLowerCase()
    const nextStatus = status ? String(status).trim().toLowerCase() : previousStatus

    const updateFields: any = { updatedAt: nowIso }
    if (status) updateFields.status = nextStatus
    if (assignedTo !== undefined) updateFields.assignedTo = assignedTo
    if (resolutionNotes !== undefined) updateFields.resolutionNotes = resolutionNotes
    if (nextStatus === 'resolved') updateFields.resolvedAt = nowIso

    const result = await db.collection('maintenance').findOneAndUpdate(
      { id },
      { $set: updateFields },
      { returnDocument: 'after', projection: { _id: 0 } }
    )

    if (!result) {
      return res.status(404).json({ error: 'Maintenance ticket not found.' })
    }

    const updated = result
    logServerEvent('MAINTENANCE', `Ticket updated [${id}]: ${previousStatus} -> ${nextStatus}, assignedTo=${assignedTo || 'none'}`)

    // Always create in-app notification on meaningful updates,
    // but ONLY send SMS when transitioning to 'in_progress' (starting) or 'resolved' (done).
    const trimmedNotes = typeof resolutionNotes === 'string' ? resolutionNotes.trim() : ''
    const isStartingTransition = previousStatus !== 'in_progress' && nextStatus === 'in_progress'
    const isDoneTransition = previousStatus !== 'resolved' && nextStatus === 'resolved'

    if (updated.tenantId && (status || assignedTo || trimmedNotes)) {
      const statusLabel = nextStatus
        .split('_')
        .map(w => w ? w.charAt(0).toUpperCase() + w.slice(1).toLowerCase() : '')
        .join(' ')
      const notifTenant = {
        id: generateHexObjectId(),
        userId: updated.tenantId,
        tenantId: updated.tenantId,
        role: 'tenant',
        type: 'maintenance_update',
        title: nextStatus === 'resolved'
          ? `Maintenance Completed: ${updated.title}`
          : nextStatus === 'in_progress'
            ? `Maintenance Started: ${updated.title}`
            : `Maintenance Update (${statusLabel}): ${updated.title}`,
        message: trimmedNotes
          ? `${trimmedNotes}${assignedTo ? ` (Technician: ${assignedTo})` : ''}`
          : nextStatus === 'resolved'
            ? `Your request for Unit ${updated.unitNumber} has been resolved by ${assignedTo || updated.assignedTo || 'our team'}.`
            : `Your maintenance request for Unit ${updated.unitNumber} is now ${statusLabel}${assignedTo ? ` (Assigned: ${assignedTo})` : ''}.`,
        timestamp: new Date().toISOString(),
        read: false,
        link: '/tenant/maintenance'
      }
      await db.collection('notifications').insertOne(notifTenant)
      broadcastServerEvent('notification', notifTenant)

      if (isStartingTransition || isDoneTransition) {
        const tenantDoc = await db.collection('tenants').findOne({ id: updated.tenantId })
        const userDoc = !tenantDoc?.phone ? await db.collection('users').findOne({ $or: [{ tenantId: updated.tenantId }, { id: updated.tenantId }] }) : null
        const phone = tenantDoc?.phone || userDoc?.phone
        if (phone) {
          const firstName = String(updated.tenantName || tenantDoc?.name || 'Resident').split(' ')[0]
          const noteSuffix = trimmedNotes ? ` ${trimmedNotes.slice(0, 160)}` : ''
          const techPart = (assignedTo || updated.assignedTo) ? ` (Technician: ${assignedTo || updated.assignedTo})` : ''
          const smsText = isDoneTransition
            ? `Hi ${firstName}, your Lapis Suites maintenance request "${updated.title}" (Unit ${updated.unitNumber}) has been resolved${techPart}.${noteSuffix}`
            : `Hi ${firstName}, work has started on your Lapis Suites maintenance request "${updated.title}" (Unit ${updated.unitNumber})${techPart}.${noteSuffix}`
          notifyTenantSms(phone, smsText, 'maintenance_update', {
            recipientEmail: tenantDoc?.email,
            userId: updated.tenantId,
            meta: { ticketId: updated.id, status: nextStatus }
          })
        }
      }
    }

    res.json(updated)
  } catch (err: any) {
    logServerEvent('MAINTENANCE', `Error updating ticket: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

export default router
