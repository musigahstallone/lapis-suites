import { Router, Response } from 'express'
import { getDb, isDbConnected } from '../db'
import { generateHexObjectId } from '../config'
import { authenticateToken, requireRole, AuthRequest, AuthUserPayload } from '../middleware/auth'
import { logServerEvent } from '../middleware/logger'

export interface AuditLogInput {
  actor?: Partial<AuthUserPayload> | { email?: string; name?: string; role?: string; userId?: string } | null
  action: string
  entityType: string
  entityId?: string | null
  summary: string
  meta?: Record<string, any>
}

export async function logAuditEvent(input: AuditLogInput): Promise<void> {
  try {
    if (!isDbConnected()) return
    const db = getDb()
    const nowIso = new Date().toISOString()
    const doc = {
      id: generateHexObjectId(),
      timestamp: nowIso,
      actorId: input.actor?.userId || null,
      actorName: input.actor?.name || 'System',
      actorEmail: input.actor?.email || 'system@lapissuites.local',
      actorRole: input.actor?.role || 'system',
      action: String(input.action || 'event').trim(),
      entityType: String(input.entityType || 'system').trim(),
      entityId: input.entityId ? String(input.entityId) : null,
      summary: String(input.summary || '').trim().slice(0, 500),
      meta: input.meta || {}
    }
    await db.collection('audit_logs').insertOne(doc)
  } catch (err: any) {
    logServerEvent('AUDIT', `Audit write notice: ${err.message}`)
  }
}

const router = Router()

// GET /api/audit-logs (Landlord only — supports ?limit, ?entityType, ?search)
router.get('/audit-logs', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const limit = Math.min(200, Math.max(1, Number(req.query.limit) || 100))
    const page = Math.max(1, Number(req.query.page) || 1)
    const entityType = req.query.entityType ? String(req.query.entityType).trim() : ''
    const search = req.query.search ? String(req.query.search).trim() : ''

    const query: any = {}
    if (entityType && entityType !== 'all') {
      query.entityType = entityType
    }
    if (search) {
      const escaped = search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      const regex = new RegExp(escaped, 'i')
      query.$or = [
        { summary: regex },
        { action: regex },
        { actorName: regex },
        { actorEmail: regex },
        { entityId: regex }
      ]
    }

    const total = await db.collection('audit_logs').countDocuments(query)
    const logs = await db.collection('audit_logs')
      .find(query, { projection: { _id: 0 } })
      .sort({ timestamp: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .toArray()

    res.setHeader('X-Total-Count', String(total))
    res.json(logs)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
