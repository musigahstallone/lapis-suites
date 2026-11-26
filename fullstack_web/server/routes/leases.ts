import { Router, Response } from 'express'
import { getDb } from '../db'
import { generateHexObjectId } from '../config'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { logServerEvent } from '../middleware/logger'
import { notifyTenantSms } from '../services/sms'
import { getRentDueDay } from '../services/settings'

const router = Router()

// Dynamic next payment due date calculator
function computeNextPaymentDueDate(startDateStr?: string, dueDay: number = 5): string {
  const base = startDateStr ? new Date(startDateStr) : new Date()
  const year = isNaN(base.getFullYear()) ? new Date().getFullYear() : base.getFullYear()
  const month = isNaN(base.getMonth()) ? new Date().getMonth() : base.getMonth()
  const target = new Date(year, month + 1, dueDay)
  const yyyy = target.getFullYear()
  const mm = String(target.getMonth() + 1).padStart(2, '0')
  const dd = String(dueDay).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}

// GET /api/leases (Landlord sees all; Tenant sees ONLY their own leases)
router.get('/leases', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    let query: any = {}

    if (user.role === 'tenant') {
      const orClauses: any[] = []
      if (user.tenantId) orClauses.push({ tenantId: user.tenantId })
      if (user.userId) orClauses.push({ tenantId: user.userId })
      if (user.unitNumber) orClauses.push({ unitNumber: user.unitNumber })
      if (orClauses.length === 0) return res.json([])
      query = { $or: orClauses }
    } else if (req.query.tenantId) {
      query.tenantId = String(req.query.tenantId)
    }

    const leases = await db.collection('leases').find(query, { projection: { _id: 0 } }).toArray()
    logServerEvent('LEASES', `Loaded ${leases.length} leases for ${user.role}`)
    res.json(leases)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// GET /api/leases/:id (Landlord sees any; Tenant sees ONLY their own lease)
router.get('/leases/:id', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    const lease = await db.collection('leases').findOne({ id: String(req.params.id) }, { projection: { _id: 0 } })
    if (!lease) return res.status(404).json({ error: 'Lease not found' })

    if (user.role === 'tenant') {
      const isOwn =
        (user.tenantId && lease.tenantId === user.tenantId) ||
        (user.userId && lease.tenantId === user.userId) ||
        (user.unitNumber && lease.unitNumber === user.unitNumber)
      if (!isOwn) {
        return res.status(403).json({ error: 'Access denied to this lease agreement.' })
      }
    }

    res.json(lease)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/leases (Landlord only)
router.post('/leases', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { tenantId, unitId, startDate, endDate, monthlyRent, depositAmount, depositPaid, terms } = req.body
    if (!tenantId || !unitId || !startDate || !endDate) {
      return res.status(400).json({ error: 'Tenant, Unit, Start Date, and End Date are required' })
    }

    const unit = await db.collection('units').findOne({ id: unitId })
    const tenant = await db.collection('tenants').findOne({ id: tenantId })
    if (!unit) return res.status(404).json({ error: 'Unit not found' })
    if (!tenant) return res.status(404).json({ error: 'Tenant not found' })

    const leaseId = generateHexObjectId()
    const leaseNumber = `LPS-L${Math.floor(1000 + Math.random() * 9000)}`
    const rentNum = Number(monthlyRent || 0)
    const depNum = Number(depositAmount || rentNum)
    const isDepositPaid = Boolean(depositPaid)

    const configuredDueDay = await getRentDueDay()
    const newLease = {
      id: leaseId,
      leaseNumber,
      tenantId,
      tenantName: tenant.name,
      unitId,
      unitNumber: unit.unitNumber,
      unitType: unit.type,
      startDate,
      endDate,
      monthlyRent: rentNum,
      depositAmount: depNum,
      depositPaid: isDepositPaid,
      status: isDepositPaid ? 'active' : 'pending_deposit',
      terms: terms || `Standard residential tenancy agreement for Unit ${unit.unitNumber}.`,
      nextPaymentDueDate: computeNextPaymentDueDate(startDate, configuredDueDay),
      createdAt: new Date().toISOString()
    }

    await db.collection('leases').insertOne(newLease)
    // Update unit to occupied
    await db.collection('units').updateOne(
      { id: unitId },
      { $set: { status: 'occupied', currentTenantId: tenantId, currentLeaseId: leaseId, updatedAt: new Date().toISOString() } }
    )
    // Update tenant assigned unit
    await db.collection('tenants').updateOne(
      { id: tenantId },
      {
        $set: {
          currentUnitId: unitId,
          currentUnitNumber: unit.unitNumber,
          currentLeaseId: leaseId,
          moveInDate: startDate,
          updatedAt: new Date().toISOString()
        }
      }
    )

    // Synchronize tenant's user login record
    await db.collection('users').updateMany(
      {
        $or: [
          { id: tenantId },
          { tenantId: tenantId },
          { email: tenant.email.toLowerCase() }
        ]
      },
      {
        $set: {
          tenantId: tenantId,
          unitNumber: unit.unitNumber,
          updatedAt: new Date().toISOString()
        }
      }
    )

    // Synchronize any duplicate tenant record sharing the same phone
    if (tenant.phone) {
      await db.collection('tenants').updateMany(
        { phone: tenant.phone },
        {
          $set: {
            currentUnitId: unitId,
            currentUnitNumber: unit.unitNumber,
            currentLeaseId: leaseId,
            updatedAt: new Date().toISOString()
          }
        }
      )
    }

    logServerEvent('LEASES', `Created lease ${leaseNumber} in MongoDB: Unit ${unit.unitNumber} -> ${tenant.name}`)

    // Notify tenant via SMS about their new lease assignment
    if (tenant.phone) {
      const firstName = String(tenant.name || 'Resident').split(' ')[0]
      notifyTenantSms(
        tenant.phone,
        `Welcome to Lapis Suites, ${firstName}! Lease ${leaseNumber} for Unit ${unit.unitNumber} is active (Rent: KES ${rentNum.toLocaleString()}/mo, next due ${newLease.nextPaymentDueDate}).`,
        'lease_notice',
        { recipientEmail: tenant.email, userId: tenant.id, meta: { leaseId, unitNumber: unit.unitNumber } }
      )
    }

    res.status(201).json(newLease)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/leases/:id/terminate (Landlord only)
router.post('/leases/:id/terminate', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const id = String(req.params.id)
    const lease = await db.collection('leases').findOne({ id })
    if (!lease) return res.status(404).json({ error: 'Lease not found' })

    const nowIso = new Date().toISOString()
    await db.collection('leases').updateOne({ id }, { $set: { status: 'terminated', terminatedAt: nowIso } })
    if (lease.unitId) {
      await db.collection('units').updateOne({ id: lease.unitId }, { $set: { status: 'vacant', currentTenantId: null, currentLeaseId: null, updatedAt: nowIso } })
    }
    if (lease.tenantId) {
      await db.collection('tenants').updateOne({ id: lease.tenantId }, { $set: { currentUnitId: null, currentUnitNumber: '', currentLeaseId: null, updatedAt: nowIso } })
    }
    logServerEvent('LEASES', `Terminated lease ${lease.leaseNumber} in MongoDB. Unit ${lease.unitNumber} marked vacant.`)
    res.json({ success: true, message: 'Lease terminated' })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/leases/transfer (Landlord only)
router.post('/leases/transfer', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { tenantId, currentUnitId, newUnitId, transferDate, newRent, depositRollOver, transferFee, transferNotes } = req.body
    if (!tenantId || !newUnitId) return res.status(400).json({ error: 'Tenant and target new unit are required' })

    const tenant = await db.collection('tenants').findOne({ id: String(tenantId) })
    const newUnit = await db.collection('units').findOne({ id: String(newUnitId) })
    if (!tenant || !newUnit) return res.status(404).json({ error: 'Tenant or target unit not found' })

    const nowIso = new Date().toISOString()
    // 1. Vacate old unit
    if (currentUnitId) {
      await db.collection('units').updateOne({ id: String(currentUnitId) }, { $set: { status: 'vacant', currentTenantId: null, currentLeaseId: null, updatedAt: nowIso } })
      await db.collection('leases').updateMany(
        { tenantId: String(tenantId), unitId: String(currentUnitId), status: 'active' },
        { $set: { status: 'transferred', transferredAt: nowIso } }
      )
    }

    // 2. Create new lease for new unit
    const newLeaseId = generateHexObjectId()
    const leaseNumber = `LPS-L${Math.floor(1000 + Math.random() * 9000)}`
    const oneYearLater = new Date()
    oneYearLater.setFullYear(oneYearLater.getFullYear() + 1)

    const newLease = {
      id: newLeaseId,
      leaseNumber,
      tenantId: String(tenantId),
      tenantName: tenant.name,
      unitId: newUnit.id,
      unitNumber: newUnit.unitNumber,
      unitType: newUnit.type,
      startDate: transferDate || nowIso.slice(0, 10),
      endDate: oneYearLater.toISOString().slice(0, 10),
      monthlyRent: Number(newRent || 0),
      depositAmount: Number(newRent || 0),
      depositPaid: Boolean(depositRollOver),
      status: 'active',
      terms: transferNotes || `Internal unit transfer to Unit ${newUnit.unitNumber}.`,
      nextPaymentDueDate: computeNextPaymentDueDate(transferDate),
      createdAt: nowIso
    }
    await db.collection('leases').insertOne(newLease)

    // 3. Occupy new unit
    await db.collection('units').updateOne({ id: newUnit.id }, { $set: { status: 'occupied', currentTenantId: String(tenantId), currentLeaseId: newLeaseId, updatedAt: nowIso } })

    // 4. Update tenant assigned unit
    await db.collection('tenants').updateOne({ id: String(tenantId) }, {
      $set: { currentUnitId: newUnit.id, currentUnitNumber: newUnit.unitNumber, currentLeaseId: newLeaseId, updatedAt: nowIso }
    })

    logServerEvent('LEASES', `Transferred resident ${tenant.name} to Unit ${newUnit.unitNumber} directly in MongoDB`)
    if (tenant.phone) {
      const firstName = String(tenant.name || 'Resident').split(' ')[0]
      notifyTenantSms(
        tenant.phone,
        `Hi ${firstName}, your Lapis Suites unit transfer to Unit ${newUnit.unitNumber} is confirmed (Lease ${leaseNumber}, Rent: KES ${Number(newRent || 0).toLocaleString()}/mo).`,
        'lease_notice',
        { recipientEmail: tenant.email, userId: tenant.id, meta: { leaseId: newLeaseId, unitNumber: newUnit.unitNumber } }
      )
    }
    res.json({ success: true, newLease })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/leases/:id/amend (Landlord only)
router.post('/leases/:id/amend', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const id = String(req.params.id)
    const { changeType, effectiveDate, newRent, newEndDate, newDeposit, reason, notes } = req.body

    const lease = await db.collection('leases').findOne({ id })
    if (!lease) return res.status(404).json({ error: 'Lease agreement not found' })

    const nowIso = new Date().toISOString()
    const amendmentId = generateHexObjectId()

    const amendment = {
      id: amendmentId,
      leaseId: id,
      leaseNumber: lease.leaseNumber,
      unitNumber: lease.unitNumber,
      tenantId: lease.tenantId,
      tenantName: lease.tenantName,
      changeType: changeType || 'rent_adjustment',
      effectiveDate: effectiveDate || nowIso.slice(0, 10),
      previousRent: lease.monthlyRent,
      newRent: newRent !== undefined && Number(newRent) > 0 ? Number(newRent) : lease.monthlyRent,
      previousEndDate: lease.endDate,
      newEndDate: newEndDate || lease.endDate,
      previousDeposit: lease.depositAmount,
      newDeposit: newDeposit !== undefined ? Number(newDeposit) : lease.depositAmount,
      reason: reason || 'Contractual amendment',
      notes: notes || '',
      createdAt: nowIso
    }

    await db.collection('lease_amendments').insertOne(amendment)

    const leaseUpdates: any = { updatedAt: nowIso }
    if (newRent !== undefined && Number(newRent) > 0) {
      leaseUpdates.monthlyRent = Number(newRent)
    }
    if (newEndDate) {
      leaseUpdates.endDate = newEndDate
    }
    if (newDeposit !== undefined && Number(newDeposit) > 0) {
      leaseUpdates.depositAmount = Number(newDeposit)
    }
    if (notes) {
      leaseUpdates.terms = `${lease.terms || ''}\n[Amendment ${effectiveDate || nowIso.slice(0, 10)}: ${reason} - ${notes}]`.trim()
    }

    await db.collection('leases').updateOne({ id }, { $set: leaseUpdates })
    const updatedLease = await db.collection('leases').findOne({ id }, { projection: { _id: 0 } })

    logServerEvent('LEASES', `Amended lease ${lease.leaseNumber} (${changeType}): ${reason}`)
    if (lease.tenantId) {
      const tenantDoc = await db.collection('tenants').findOne({ id: lease.tenantId })
      if (tenantDoc?.phone) {
        const firstName = String(tenantDoc.name || lease.tenantName || 'Resident').split(' ')[0]
        notifyTenantSms(
          tenantDoc.phone,
          `Hi ${firstName}, Lapis Suites updated Lease ${lease.leaseNumber} (Unit ${lease.unitNumber}) effective ${amendment.effectiveDate}: ${amendment.reason}.`,
          'lease_notice',
          { recipientEmail: tenantDoc.email, userId: tenantDoc.id, meta: { leaseId: id, amendmentId } }
        )
      }
    }
    res.json({ success: true, amendment, lease: updatedLease })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// GET /api/leases-amendments (Landlord only)
router.get('/leases-amendments', authenticateToken, requireRole(['landlord']), async (_req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const amendments = await db.collection('lease_amendments').find({}, { projection: { _id: 0 } }).sort({ createdAt: -1 }).toArray()
    res.json(amendments)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
