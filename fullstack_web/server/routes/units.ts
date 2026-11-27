import { Router, Response } from 'express'
import { getDb } from '../db'
import { generateHexObjectId } from '../config'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { logServerEvent } from '../middleware/logger'
import { logAuditEvent } from '../services/audit'

const router = Router()

// GET /api/units (Landlord sees all; Tenant sees only their assigned unit)
router.get('/units', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    let query: any = {}

    if (user.role === 'tenant') {
      const orClauses: any[] = []
      if (user.tenantId) orClauses.push({ currentTenantId: user.tenantId })
      if (user.userId) orClauses.push({ currentTenantId: user.userId })
      if (orClauses.length === 0) return res.json([])
      query = { $or: orClauses }
    }

    const units = await db.collection('units').find(query, { projection: { _id: 0 } }).toArray()
    logServerEvent('UNITS', `Loaded ${units.length} units for ${user.role}`)
    res.json(units)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// GET /api/units/:id (Landlord sees any; Tenant sees only their assigned unit)
router.get('/units/:id', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    const unit = await db.collection('units').findOne({ id: String(req.params.id) }, { projection: { _id: 0 } })
    if (!unit) return res.status(404).json({ error: 'Unit not found' })

    if (user.role === 'tenant') {
      const isOwn =
        (user.tenantId && unit.currentTenantId === user.tenantId) ||
        (user.userId && unit.currentTenantId === user.userId) ||
        (user.unitNumber && unit.unitNumber === user.unitNumber)
      if (!isOwn) {
        return res.status(403).json({ error: 'Access denied to this unit.' })
      }
    }

    res.json(unit)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/units (Landlord only — new units always start as 'vacant' until a lease is assigned)
router.post('/units', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { unitNumber, type } = req.body
    if (!unitNumber || !type) return res.status(400).json({ error: 'Unit number and type are required' })

    const cleanNumber = String(unitNumber).trim().toUpperCase()
    const cleanType = String(type).trim()
    const existing = await db.collection('units').findOne({ unitNumber: cleanNumber })
    if (existing) {
      return res.status(409).json({ error: `Unit ${cleanNumber} already exists in the system` })
    }

    const typeExists = await db.collection('unit_types').findOne({ key: cleanType })
    if (!typeExists) {
      return res.status(400).json({ error: `Unit type "${cleanType}" does not exist. Create or select a valid unit type first.` })
    }

    const newUnit = {
      id: generateHexObjectId(),
      unitNumber: cleanNumber,
      type: cleanType,
      status: 'vacant',
      currentTenantId: null,
      currentLeaseId: null,
      createdAt: new Date().toISOString()
    }
    await db.collection('units').insertOne(newUnit)
    logServerEvent('UNITS', `Created unit in MongoDB: ${cleanNumber} (${cleanType})`)
    await logAuditEvent({
      actor: req.user,
      action: 'unit.create',
      entityType: 'unit',
      entityId: newUnit.id,
      summary: `Created unit ${cleanNumber} (${cleanType})`
    })
    res.status(201).json(newUnit)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// PUT /api/units/:id (Landlord only — status CANNOT be updated manually; managed strictly via leases)
router.put('/units/:id', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const id = String(req.params.id)
    const { unitNumber, type, status } = req.body

    const existing = await db.collection('units').findOne({ id })
    if (!existing) return res.status(404).json({ error: 'Unit not found' })

    // Strict rule: unit occupancy status is ONLY updated by lease creation/transfer/termination
    if (status !== undefined && String(status).trim().toLowerCase() !== String(existing.status || '').toLowerCase()) {
      return res.status(400).json({
        error: 'Unit status cannot be updated manually. Occupancy is managed strictly through leases.'
      })
    }

    const isOccupied = existing.status === 'occupied' || Boolean(existing.currentTenantId) || Boolean(existing.currentLeaseId)
    const updates: any = { updatedAt: new Date().toISOString() }

    if (unitNumber !== undefined) {
      const cleanNumber = String(unitNumber).trim().toUpperCase()
      if (cleanNumber && cleanNumber !== existing.unitNumber) {
        if (isOccupied) {
          return res.status(409).json({
            error: `Cannot rename Unit ${existing.unitNumber} while occupied under an active lease.`
          })
        }
        const [leaseRefs, txRefs] = await Promise.all([
          db.collection('leases').countDocuments({ $or: [{ unitId: id }, { unitNumber: existing.unitNumber }] }),
          db.collection('transactions').countDocuments({ $or: [{ unitId: id }, { unitNumber: existing.unitNumber }] })
        ])
        if (leaseRefs > 0 || txRefs > 0) {
          return res.status(409).json({
            error: `Cannot rename Unit ${existing.unitNumber} because historical lease or payment records reference it.`
          })
        }
        const dup = await db.collection('units').findOne({ unitNumber: cleanNumber, id: { $ne: id } })
        if (dup) {
          return res.status(409).json({ error: `Unit ${cleanNumber} already exists in the system.` })
        }
        updates.unitNumber = cleanNumber
      }
    }

    if (type !== undefined) {
      const cleanType = String(type).trim()
      if (cleanType && cleanType !== existing.type) {
        if (isOccupied) {
          return res.status(400).json({
            error: `Cannot change the unit type of Unit ${existing.unitNumber} while occupied under an active lease.`
          })
        }
        const typeExists = await db.collection('unit_types').findOne({ key: cleanType })
        if (!typeExists) {
          return res.status(400).json({ error: `Unit type "${cleanType}" does not exist.` })
        }
        updates.type = cleanType
      }
    }

    const result = await db.collection('units').findOneAndUpdate(
      { id },
      { $set: updates },
      { returnDocument: 'after', projection: { _id: 0 } }
    )
    logServerEvent('UNITS', `Updated unit ${id} in MongoDB`)
    res.json(result)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// DELETE /api/units/:id (Landlord only — protects historical leases & payments from orphaned references)
router.delete('/units/:id', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const id = String(req.params.id)

    const unit = await db.collection('units').findOne({ id })
    if (!unit) return res.status(404).json({ error: 'Unit not found' })

    if (unit.status === 'occupied' || unit.currentTenantId) {
      return res.status(400).json({ error: `Cannot delete Unit ${unit.unitNumber} while currently occupied by a resident.` })
    }

    const activeLease = await db.collection('leases').findOne({ unitId: id, status: { $in: ['active', 'pending_deposit'] } })
    if (activeLease) {
      return res.status(400).json({ error: `Cannot delete Unit ${unit.unitNumber} with an active lease agreement.` })
    }

    const [historicalLeases, historicalTxs] = await Promise.all([
      db.collection('leases').countDocuments({ unitId: id }),
      db.collection('transactions').countDocuments({ unitId: id })
    ])
    if (historicalLeases > 0 || historicalTxs > 0) {
      return res.status(409).json({
        error: `Cannot delete Unit ${unit.unitNumber} because ${historicalLeases} lease record(s) and ${historicalTxs} payment record(s) reference it. Keep it vacant to preserve financial history.`
      })
    }

    await db.collection('units').deleteOne({ id })
    logServerEvent('UNITS', `Deleted Unit ${unit.unitNumber} (${id}) from MongoDB`)
    await logAuditEvent({
      actor: req.user,
      action: 'unit.delete',
      entityType: 'unit',
      entityId: id,
      summary: `Deleted vacant unit ${unit.unitNumber}`
    })
    res.json({ success: true, message: `Unit ${unit.unitNumber} deleted successfully.` })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// GET /api/unit-types (Authenticated users — includes unitCount & occupiedCount for safe CRUD)
router.get('/unit-types', authenticateToken, async (_req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const [unitTypes, units] = await Promise.all([
      db.collection('unit_types').find({}, { projection: { _id: 0 } }).toArray(),
      db.collection('units').find({}, { projection: { type: 1, status: 1, currentTenantId: 1 } }).toArray()
    ])

    const enriched = unitTypes.map((ut: any) => {
      const matching = units.filter((u: any) => String(u.type || '').toLowerCase() === String(ut.key || '').toLowerCase())
      const occupiedCount = matching.filter((u: any) => u.status === 'occupied' || Boolean(u.currentTenantId)).length
      return {
        ...ut,
        unitCount: matching.length,
        occupiedCount
      }
    })

    res.json(enriched)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

async function saveUnitTypeHandler(req: AuthRequest, res: Response, explicitId?: string) {
  try {
    const db = getDb()
    const targetId = explicitId || (req.body.id ? String(req.body.id) : '')
    const { name, baseRent, depositMultiplier, description, features } = req.body

    if (!name || !String(name).trim()) {
      return res.status(400).json({ error: 'Display name is required.' })
    }

    const numericRent = Number(baseRent ?? 0)
    if (!Number.isFinite(numericRent) || numericRent <= 0) {
      return res.status(400).json({ error: 'Base monthly rent must be a positive amount.' })
    }

    const numericDep = Number(depositMultiplier ?? 1)
    if (!Number.isFinite(numericDep) || numericDep < 0 || numericDep > 12) {
      return res.status(400).json({ error: 'Deposit multiplier must be between 0 and 12.' })
    }

    const cleanName = String(name).trim()
    const parsedFeatures = Array.isArray(features)
      ? features.map((f: any) => String(f).trim()).filter(Boolean)
      : (typeof features === 'string'
        ? features.split(',').map((f: string) => f.trim()).filter(Boolean)
        : [])

    if (targetId) {
      const existing = await db.collection('unit_types').findOne({ id: targetId })
      if (!existing) {
        return res.status(404).json({ error: 'Unit type not found.' })
      }

      const matchingUnits = await db.collection('units').find({ type: existing.key }).toArray()
      const unitCount = matchingUnits.length
      const occupiedCount = matchingUnits.filter((u: any) => u.status === 'occupied' || Boolean(u.currentTenantId)).length

      // Guard DB integrity: NEVER mutate key when units reference this type, and block baseRent/deposit mutations if occupied units exist
      const requestedKey = req.body.key ? String(req.body.key).trim().toLowerCase() : existing.key
      if (unitCount > 0 && requestedKey !== existing.key) {
        return res.status(409).json({
          error: `Cannot change the key of "${existing.name}" because ${unitCount} unit(s) reference it.`
        })
      }

      if (occupiedCount > 0) {
        const rentChanged = Number(existing.baseRent || 0) !== numericRent
        const depChanged = Number(existing.depositMultiplier ?? 1) !== numericDep
        if (rentChanged || depChanged) {
          return res.status(409).json({
            error: `Cannot alter base rent or deposit multiplier on "${existing.name}" while ${occupiedCount} unit(s) are occupied. Only name, description, and features can be updated safely.`
          })
        }
      }

      const updates = {
        name: cleanName,
        key: unitCount > 0 ? existing.key : requestedKey,
        baseRent: numericRent,
        depositMultiplier: numericDep,
        description: String(description ?? existing.description ?? '').trim(),
        features: features !== undefined ? parsedFeatures : (existing.features || []),
        updatedAt: new Date().toISOString()
      }

      await db.collection('unit_types').updateOne({ id: targetId }, { $set: updates })
      const saved = await db.collection('unit_types').findOne({ id: targetId }, { projection: { _id: 0 } })
      logServerEvent('UNIT-TYPES', `Updated unit type: ${saved?.key} (${cleanName}) [units=${unitCount}, occupied=${occupiedCount}]`)
      return res.json({ ...saved, unitCount, occupiedCount })
    }

    // Create new unit type
    const key = req.body.key
      ? String(req.body.key).trim().toLowerCase().replace(/[^a-z0-9-]+/g, '-')
      : (cleanName.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '') || generateHexObjectId())

    const duplicate = await db.collection('unit_types').findOne({ key })
    if (duplicate) {
      return res.status(409).json({ error: `A unit type with key "${key}" already exists.` })
    }

    const newDoc = {
      id: generateHexObjectId(),
      name: cleanName,
      key,
      baseRent: numericRent,
      depositMultiplier: numericDep,
      description: String(description || '').trim(),
      features: parsedFeatures,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    }
    await db.collection('unit_types').insertOne(newDoc)
    const saved = await db.collection('unit_types').findOne({ id: newDoc.id }, { projection: { _id: 0 } })
    logServerEvent('UNIT-TYPES', `Created unit type: ${saved?.key} (${cleanName})`)
    res.status(201).json({ ...saved, unitCount: 0, occupiedCount: 0 })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
}

// POST /api/unit-types (Landlord only — create or upsert by id)
router.post('/unit-types', authenticateToken, requireRole(['landlord']), (req: AuthRequest, res: Response) => {
  return saveUnitTypeHandler(req, res)
})

// PUT /api/unit-types/:id (Landlord only — update with occupied-unit integrity guard)
router.put('/unit-types/:id', authenticateToken, requireRole(['landlord']), (req: AuthRequest, res: Response) => {
  return saveUnitTypeHandler(req, res, String(req.params.id))
})

// DELETE /api/unit-types/:id (Landlord only — blocked if any unit uses this type)
router.delete('/unit-types/:id', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const id = String(req.params.id)
    const existing = await db.collection('unit_types').findOne({ id })
    if (!existing) {
      return res.status(404).json({ error: 'Unit type not found.' })
    }

    const unitCount = await db.collection('units').countDocuments({ type: existing.key })
    if (unitCount > 0) {
      return res.status(409).json({
        error: `Cannot delete "${existing.name}" because ${unitCount} unit(s) currently use this type. Reassign or remove those units first.`
      })
    }

    const activeLeases = await db.collection('leases').countDocuments({
      unitType: existing.key,
      status: { $in: ['active', 'pending_deposit'] }
    })
    if (activeLeases > 0) {
      return res.status(409).json({
        error: `Cannot delete "${existing.name}" because ${activeLeases} active lease(s) reference it.`
      })
    }

    await db.collection('unit_types').deleteOne({ id })
    logServerEvent('UNIT-TYPES', `Deleted unit type: ${existing.key} (${existing.name})`)
    res.json({ success: true, message: `Unit type "${existing.name}" deleted.` })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
