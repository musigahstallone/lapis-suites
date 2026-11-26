import { Router, Request, Response } from 'express'
import { getDb, isDbConnected } from '../db'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { logServerEvent } from '../middleware/logger'

const router = Router()

// GET /api/health (Public minimal health check — no internal DB host/name exposure)
router.get('/health', (_req: Request, res: Response) => {
  res.json({
    status: 'online',
    database: isDbConnected() ? 'connected' : 'disconnected',
    timestamp: new Date().toISOString()
  })
})

// GET /api/dashboard/stats (Landlord / Admin only)
router.get('/dashboard/stats', authenticateToken, requireRole(['landlord']), async (_req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const [units, tenants, leases, transactions, unitTypes] = await Promise.all([
      db.collection('units').find({}, { projection: { _id: 0 } }).toArray(),
      db.collection('tenants').find({}, { projection: { _id: 0 } }).toArray(),
      db.collection('leases').find({}, { projection: { _id: 0 } }).toArray(),
      db.collection('transactions').find({}, { projection: { _id: 0 } }).toArray(),
      db.collection('unit_types').find({}, { projection: { _id: 0 } }).toArray()
    ])

    logServerEvent('DASHBOARD', `Loaded stats: ${units.length} units, ${tenants.length} tenants, ${leases.length} leases, ${transactions.length} txs`)
    res.json({ units, tenants, leases, transactions, unitTypes })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
