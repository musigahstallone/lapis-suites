import crypto from 'crypto'
import { Router, Response } from 'express'
import bcrypt from 'bcryptjs'
import { getDb } from '../db'
import { generateHexObjectId } from '../config'
import { logServerEvent } from '../middleware/logger'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { getRentDueDay } from '../services/settings'
import { logAuditEvent } from '../services/audit'
import { parsePositiveAmount, cleanString, isValidEnum, isValidEmail } from '../middleware/validate'

// Dynamic next payment due date calculator
function computeNextPaymentDueDate(dueDay: number = 5): string {
  const now = new Date()
  const target = new Date(now.getFullYear(), now.getMonth() + 1, dueDay)
  const yyyy = target.getFullYear()
  const mm = String(target.getMonth() + 1).padStart(2, '0')
  const dd = String(dueDay).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}

const router = Router()

// GET /api/tenants (Landlord sees all; Tenant sees ONLY their own profile)
router.get('/tenants', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    let query: any = {}

    if (user.role === 'tenant') {
      const orClauses: any[] = []
      if (user.tenantId) orClauses.push({ id: user.tenantId })
      if (user.userId) orClauses.push({ id: user.userId })
      if (user.email) orClauses.push({ email: user.email.toLowerCase() })
      if (orClauses.length === 0) return res.json([])
      query = { $or: orClauses }
    }

    const tenants = await db.collection('tenants').find(query, { projection: { _id: 0 } }).toArray()
    logServerEvent('TENANTS', `Loaded ${tenants.length} tenants for ${user.role}`)
    res.json(tenants)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// GET /api/tenants/:id (Landlord sees any; Tenant sees ONLY their own record)
router.get('/tenants/:id', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    const id = String(req.params.id)
    const tenant = await db.collection('tenants').findOne({ id }, { projection: { _id: 0 } })
    if (!tenant) return res.status(404).json({ error: 'Tenant not found' })

    if (user.role === 'tenant') {
      const isOwn =
        (user.tenantId && tenant.id === user.tenantId) ||
        (user.userId && tenant.id === user.userId) ||
        (user.email && tenant.email && tenant.email.toLowerCase() === user.email.toLowerCase())
      if (!isOwn) {
        return res.status(403).json({ error: 'Access denied to this resident profile.' })
      }
    }

    res.json(tenant)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/tenants (Landlord only)
router.post('/tenants', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { name, email, phone, nationalId, currentUnitId } = req.body
    if (!name || !email) return res.status(400).json({ error: 'Name and email are required' })

    const cleanEmail = String(email).trim().toLowerCase()
    const existing = await db.collection('tenants').findOne({ email: cleanEmail })
    if (existing) return res.status(409).json({ error: `A resident with email ${cleanEmail} already exists` })

    const newTenantId = generateHexObjectId()
    const initials = String(name).trim().split(' ').map((p: string) => p[0]).join('').slice(0, 2).toUpperCase() || 'TN'

    let unitDoc = null
    if (currentUnitId) {
      unitDoc = await db.collection('units').findOne({ id: String(currentUnitId) })
    }

    const newTenant = {
      id: newTenantId,
      name: String(name).trim(),
      email: cleanEmail,
      phone: String(phone || '').trim(),
      nationalId: nationalId ? String(nationalId).trim() : 'ID-PENDING',
      currentUnitId: unitDoc ? unitDoc.id : null,
      currentUnitNumber: unitDoc ? unitDoc.unitNumber : '',
      currentLeaseId: null,
      balance: 0,
      arrearsBalance: 0,
      accountCredit: 0,
      nextPaymentDueDate: computeNextPaymentDueDate(),
      status: 'active',
      moveInDate: new Date().toISOString().slice(0, 10),
      avatarInitials: initials,
      createdAt: new Date().toISOString()
    }
    await db.collection('tenants').insertOne(newTenant)

    // Auto-provision unclaimed tenant login with an unguessable random password hash (forces SMS OTP account claim)
    const unusableRandomPasswordHash = bcrypt.hashSync(crypto.randomBytes(32).toString('hex'), 10)
    await db.collection('users').updateOne(
      { email: cleanEmail },
      {
        $setOnInsert: {
          id: newTenantId,
          email: cleanEmail,
          passwordHash: unusableRandomPasswordHash,
          name: newTenant.name,
          phone: newTenant.phone || '',
          role: 'tenant',
          accountClaimed: false,
          tenantId: newTenantId,
          unitNumber: newTenant.currentUnitNumber || '',
          avatarInitials: initials,
          createdAt: new Date().toISOString()
        }
      },
      { upsert: true }
    )

    logServerEvent('TENANTS', `Added new resident in MongoDB: ${newTenant.name} (${newTenant.email}) with OTP-claim portal access`)
    res.status(201).json(newTenant)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// PUT /api/tenants/:id (Role-based profile editing)
router.put('/tenants/:id', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { id } = req.params
    const user = req.user

    const tenant = await db.collection('tenants').findOne({ id })
    if (!tenant) return res.status(404).json({ error: 'Tenant not found' })

    const updates: any = { updatedAt: new Date().toISOString() }

    if (user?.role === 'tenant') {
      // Tenant permissions: ONLY email and other phone numbers
      if (user.tenantId && user.tenantId !== id && user.userId !== id) {
        return res.status(403).json({ error: 'You are only authorized to update your own resident profile.' })
      }

      const { email, otherPhone, emergencyContact } = req.body
      if (email) {
        const cleanEmail = String(email).trim().toLowerCase()
        updates.email = cleanEmail
        await db.collection('users').updateOne(
          { $or: [{ id }, { tenantId: id }, { email: tenant.email }] },
          { $set: { email: cleanEmail } }
        )
      }
      if (otherPhone !== undefined) updates.otherPhone = String(otherPhone).trim()
      if (emergencyContact !== undefined) updates.emergencyContact = String(emergencyContact).trim()

      logServerEvent('TENANTS', `Tenant ${id} updated personal contact details (email/other numbers)`)
    } else {
      // Landlord permissions: Full administrative authority over name, primary phone, email, ID number, and status
      const { name, email, phone, nationalId, otherPhone, emergencyContact, status } = req.body
      if (name) {
        updates.name = String(name).trim()
        updates.avatarInitials = String(name).trim().split(' ').map((p: string) => p[0]).join('').slice(0, 2).toUpperCase()
      }
      if (email) {
        const cleanEmail = String(email).trim().toLowerCase()
        updates.email = cleanEmail
        await db.collection('users').updateOne(
          { $or: [{ id }, { tenantId: id }, { email: tenant.email }] },
          { $set: { email: cleanEmail } }
        )
      }
      if (phone !== undefined) updates.phone = String(phone).trim()
      if (nationalId !== undefined) updates.nationalId = String(nationalId).trim()
      if (otherPhone !== undefined) updates.otherPhone = String(otherPhone).trim()
      if (emergencyContact !== undefined) updates.emergencyContact = String(emergencyContact).trim()
      if (status !== undefined) updates.status = status

      if (updates.name) {
        await db.collection('users').updateOne(
          { $or: [{ id }, { tenantId: id }, { email: tenant.email }] },
          { $set: { name: updates.name, avatarInitials: updates.avatarInitials } }
        )
      }

      logServerEvent('TENANTS', `Landlord updated tenant ${id} profile (Name, Primary Phone, ID, Email)`)
    }

    const result = await db.collection('tenants').findOneAndUpdate(
      { id },
      { $set: updates },
      { returnDocument: 'after', projection: { _id: 0 } }
    )
    res.json(result)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// Helper: parse YYYY-MM-DD safely into UTC midnight Date
function parseIsoDateOnly(raw?: string): Date | null {
  if (!raw) return null
  const m = String(raw).trim().match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (!m) return null
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])))
  return isNaN(d.getTime()) ? null : d
}

// Helper: compute billable months strictly within [startDate, min(today, endDate)]
function computeBillableMonthsForLease(startDateStr?: string, endDateStr?: string, nowRef: Date = new Date()): number {
  const start = parseIsoDateOnly(startDateStr)
  if (!start) return 1

  const todayUtc = new Date(Date.UTC(nowRef.getUTCFullYear(), nowRef.getUTCMonth(), nowRef.getUTCDate()))
  // If lease has not started yet, 0 rent months have accrued
  if (todayUtc.getTime() < start.getTime()) {
    return 0
  }

  const end = parseIsoDateOnly(endDateStr)
  const effectiveEnd = (end && todayUtc.getTime() > end.getTime()) ? end : todayUtc

  let months =
    (effectiveEnd.getUTCFullYear() - start.getUTCFullYear()) * 12 +
    (effectiveEnd.getUTCMonth() - start.getUTCMonth()) +
    1

  // Cap at total lease term months when endDate is specified
  if (end && end.getTime() >= start.getTime()) {
    const termMonths = Math.max(
      1,
      (end.getUTCFullYear() - start.getUTCFullYear()) * 12 +
      (end.getUTCMonth() - start.getUTCMonth()) +
      (end.getUTCDate() >= start.getUTCDate() ? 1 : 0)
    )
    months = Math.min(months, termMonths)
  }

  return Math.max(1, months)
}

// Comprehensive multi-unit, date-bounded ledger & deposit reconciliation logic
export async function runTenantLedgerReconciliation(
  id: string,
  options?: { targetLeaseId?: string | null; targetUnitNumber?: string | null }
) {
  const db = getDb()

  const tenant = await db.collection('tenants').findOne({ id })
  if (!tenant) throw new Error('Tenant not found')

  // Load ALL active/pending_deposit leases for this tenant sorted by startDate (first = default lease)
  let leases = await db.collection('leases')
    .find({
      tenantId: id,
      status: { $in: ['active', 'pending_deposit', 'pending'] }
    })
    .sort({ startDate: 1, createdAt: 1 })
    .toArray()

  if (leases.length === 0) {
    const fallbackLease = await db.collection('leases').findOne({ tenantId: id }, { sort: { createdAt: -1 } })
    if (fallbackLease) leases = [fallbackLease]
  }

  const primaryLease = leases[0] || null
  const leaseIds = leases.map((l: any) => l.id).filter(Boolean)
  const leaseUnitNumbers = leases.map((l: any) => l.unitNumber).filter(Boolean)

  // 1. Gather ONLY verified transactions belonging strictly to THIS tenant (NEVER cross-match by shared phone!)
  const queryConditions: any[] = [{ tenantId: id }]
  if (leaseIds.length > 0) {
    queryConditions.push({ leaseId: { $in: leaseIds } })
  }
  if (leaseUnitNumbers.length > 0) {
    // Only include unassigned/null tenantId transactions matching this tenant's leased units
    queryConditions.push({ tenantId: null, unitNumber: { $in: leaseUnitNumbers } })
  }

  const allTxs = await db.collection('transactions').find({
    $or: queryConditions,
    status: { $in: ['reconciled', 'completed', 'paid'] }
  }).sort({ date: 1, timestamp: 1, _id: 1 }).toArray()

  const rentDueDay = await getRentDueDay()
  const nowIso = new Date().toISOString()

  // Determine the default target lease when a transaction has no explicit unit/lease match
  const defaultLease =
    (options?.targetLeaseId ? leases.find((l: any) => l.id === options.targetLeaseId) : null) ||
    (options?.targetUnitNumber ? leases.find((l: any) => l.unitNumber === options.targetUnitNumber) : null) ||
    primaryLease

  // Bucket transactions strictly to their corresponding lease (so multi-unit tenants never cross-corrupt)
  const txByLeaseId = new Map<string, any[]>()
  for (const l of leases) txByLeaseId.set(l.id, [])

  for (const tx of allTxs) {
    let matchedLease =
      (tx.leaseId ? leases.find((l: any) => l.id === tx.leaseId) : null) ||
      (tx.unitNumber ? leases.find((l: any) => l.unitNumber === tx.unitNumber) : null) ||
      (tx.billRefNumber ? leases.find((l: any) => l.unitNumber === tx.billRefNumber || `LAPIS-${l.unitNumber}` === tx.billRefNumber) : null) ||
      defaultLease

    if (matchedLease) {
      txByLeaseId.get(matchedLease.id)!.push(tx)
    }
  }

  // 1b. Load manual ledger adjustments (extra charges / credits / waivers — no automatic late fees)
  const allAdjustments = await db.collection('ledger_adjustments')
    .find({ tenantId: id })
    .sort({ createdAt: 1 })
    .toArray()

  const adjByLeaseId = new Map<string, any[]>()
  for (const l of leases) adjByLeaseId.set(l.id, [])
  const unattachedAdjustments: any[] = []
  for (const adj of allAdjustments) {
    const matched =
      (adj.leaseId ? leases.find((l: any) => l.id === adj.leaseId) : null) ||
      (adj.unitNumber ? leases.find((l: any) => l.unitNumber === adj.unitNumber) : null) ||
      primaryLease
    if (matched) {
      adjByLeaseId.get(matched.id)!.push(adj)
    } else {
      unattachedAdjustments.push(adj)
    }
  }

  let aggregatePaid = 0
  let aggregateBilled = 0
  let aggregateBalance = 0
  let aggregateCredit = 0
  let earliestNextDueDate = ''
  let primaryUpdatedLease: any = null

  if (leases.length === 0) {
    // Tenant has no leases: any reconciled payments & credits count as account credit minus charges
    const basePaid = allTxs.reduce((sum, tx) => sum + Number(tx.amount || 0), 0)
    const adjCharges = unattachedAdjustments.filter((a: any) => a.type === 'charge').reduce((s, a) => s + Number(a.amount || 0), 0)
    const adjCredits = unattachedAdjustments.filter((a: any) => a.type === 'credit').reduce((s, a) => s + Number(a.amount || 0), 0)
    aggregatePaid = basePaid + adjCredits
    aggregateBilled = adjCharges
    const diff = aggregatePaid - aggregateBilled
    aggregateBalance = diff < 0 ? Math.abs(diff) : 0
    aggregateCredit = diff > 0 ? diff : 0
  } else {
    for (const lease of leases) {
      const leaseTxs = txByLeaseId.get(lease.id) || []
      const leaseAdjs = adjByLeaseId.get(lease.id) || []
      const leaseCharges = leaseAdjs.filter((a: any) => a.type === 'charge').reduce((s, a) => s + Number(a.amount || 0), 0)
      const leaseCredits = leaseAdjs.filter((a: any) => a.type === 'credit').reduce((s, a) => s + Number(a.amount || 0), 0)
      const leasePaidRaw = leaseTxs.reduce((sum, tx) => sum + Number(tx.amount || 0), 0)
      const leasePaid = leasePaidRaw + leaseCredits
      const monthlyRent = Number(lease.monthlyRent || 0)
      const depositAmount = Number(lease.depositAmount !== undefined ? lease.depositAmount : monthlyRent)
      const monthsBilled = computeBillableMonthsForLease(lease.startDate || tenant.moveInDate, lease.endDate)
      const leaseBilled = depositAmount + (monthsBilled * monthlyRent) + leaseCharges

      const depositPaid = leasePaid >= depositAmount
      const depositStatus = depositPaid ? 'paid' : (leasePaid > 0 ? 'partially_paid' : 'pending')
      const leaseStatus =
        lease.status === 'terminated' || lease.status === 'transferred'
          ? lease.status
          : (depositPaid ? 'active' : 'pending_deposit')

      let runningPaid = 0
      for (const tx of leaseTxs) {
        const prevPaid = runningPaid
        runningPaid += Number(tx.amount || 0)

        let paymentType = 'rent'
        let notes = tx.notes || `Payment for Unit ${lease.unitNumber}`
        if (prevPaid < depositAmount) {
          if (runningPaid <= depositAmount) {
            paymentType = 'deposit'
            notes = `Security Deposit (${tx.reference || 'Ref'})`
          } else {
            paymentType = 'deposit_and_rent'
            const depositPart = depositAmount - prevPaid
            const rentPart = Number(tx.amount || 0) - depositPart
            notes = `Deposit (KES ${depositPart}) + Rent (KES ${rentPart})`
          }
        } else {
          paymentType = 'rent'
          notes = `Rent (${tx.reference || 'Ref'})`
        }

        await db.collection('transactions').updateOne(
          { _id: tx._id },
          {
            $set: {
              tenantId: id,
              tenantName: tenant.name,
              leaseId: lease.id,
              unitId: lease.unitId || tx.unitId || null,
              unitNumber: lease.unitNumber || tx.unitNumber || '',
              status: 'reconciled',
              reconciled: true,
              paymentType,
              notes
            }
          }
        )
      }

      const diff = leasePaid - leaseBilled
      const leaseBalance = diff < 0 ? Math.abs(diff) : 0
      const leaseCredit = diff > 0 ? diff : 0

      // Compute next due date respecting startDate, prepaid months, and endDate cap
      const startDateObj = parseIsoDateOnly(lease.startDate || tenant.moveInDate) || new Date()
      const endDateObj = parseIsoDateOnly(lease.endDate)
      let monthsToAdvance = Math.max(1, monthsBilled)
      if (monthlyRent > 0 && leaseCredit >= monthlyRent) {
        monthsToAdvance += Math.floor(leaseCredit / monthlyRent)
      }
      let nextDueObj = new Date(Date.UTC(startDateObj.getUTCFullYear(), startDateObj.getUTCMonth() + monthsToAdvance, rentDueDay))
      if (endDateObj && nextDueObj.getTime() > endDateObj.getTime()) {
        nextDueObj = endDateObj
      }
      const leaseNextDue = `${nextDueObj.getUTCFullYear()}-${String(nextDueObj.getUTCMonth() + 1).padStart(2, '0')}-${String(nextDueObj.getUTCDate()).padStart(2, '0')}`

      await db.collection('leases').updateOne(
        { id: lease.id },
        {
          $set: {
            tenantId: id,
            tenantName: tenant.name,
            depositPaid,
            depositStatus,
            status: leaseStatus,
            leasePaid,
            leaseBilled,
            leaseBalance,
            leaseCredit,
            monthsBilled,
            nextPaymentDueDate: leaseNextDue,
            updatedAt: nowIso
          }
        }
      )

      const updatedDoc = await db.collection('leases').findOne({ id: lease.id }, { projection: { _id: 0 } })
      if (!primaryUpdatedLease || lease.id === defaultLease?.id) {
        primaryUpdatedLease = updatedDoc
      }

      aggregatePaid += leasePaid
      aggregateBilled += leaseBilled
      aggregateBalance += leaseBalance
      aggregateCredit += leaseCredit
      if (!earliestNextDueDate || leaseNextDue < earliestNextDueDate) {
        earliestNextDueDate = leaseNextDue
      }
    }
  }

  const nextPaymentDueDate = earliestNextDueDate || computeNextPaymentDueDate(rentDueDay)
  const balance = aggregateBalance
  const arrearsBalance = aggregateBalance
  const accountCredit = aggregateBalance > 0 ? 0 : aggregateCredit
  const updatedLease = primaryUpdatedLease

  // 7. Update Tenant Record in MongoDB
  await db.collection('tenants').updateOne(
    { id },
    {
      $set: {
        balance,
        arrearsBalance,
        accountCredit,
        nextPaymentDueDate,
        unitNumbers: leaseUnitNumbers,
        updatedAt: nowIso
      }
    }
  )
  const updatedTenant = await db.collection('tenants').findOne({ id }, { projection: { _id: 0 } })

  logServerEvent('RECONCILE', `Reconciled ${tenant.name} (${leases.length} lease(s)): Paid KES ${aggregatePaid}, Billed KES ${aggregateBilled}, Balance KES ${balance}, Credit KES ${accountCredit}, Next Due ${nextPaymentDueDate}`)

  return {
    success: true,
    tenant: updatedTenant,
    lease: updatedLease,
    summary: {
      totalPaid: aggregatePaid,
      totalBilled: aggregateBilled,
      depositAmount: Number(updatedLease?.depositAmount || 0),
      depositPaid: Boolean(updatedLease?.depositPaid),
      monthsBilled: Number(updatedLease?.monthsBilled || 0),
      accountCredit,
      balance,
      nextPaymentDueDate
    }
  }
}

// POST /api/tenants/reconcile-all (Landlord only — single-request batch reconciliation across all residents)
router.post('/tenants/reconcile-all', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const tenants = await db.collection('tenants').find({}, { projection: { id: 1, name: 1 } }).toArray()
    let reconciledCount = 0
    let totalArrears = 0
    let totalCredit = 0
    const errors: string[] = []

    for (const t of tenants) {
      try {
        const r = await runTenantLedgerReconciliation(String(t.id))
        reconciledCount++
        totalArrears += Number(r.summary?.balance || 0)
        totalCredit += Number(r.summary?.accountCredit || 0)
      } catch (e: any) {
        errors.push(`${t.name || t.id}: ${e.message}`)
      }
    }

    logServerEvent('RECONCILE', `Batch reconciled ${reconciledCount}/${tenants.length} residents (Arrears: KES ${totalArrears}, Credit: KES ${totalCredit})`)
    await logAuditEvent({
      actor: req.user,
      action: 'ledger.reconcile_all',
      entityType: 'ledger',
      summary: `Batch reconciled ${reconciledCount} resident ledgers (Total Arrears: KES ${Math.round(totalArrears).toLocaleString()})`,
      meta: { reconciledCount, totalTenants: tenants.length, totalArrears, totalCredit, errorCount: errors.length }
    })

    res.json({
      ok: true,
      reconciledCount,
      totalTenants: tenants.length,
      totalArrears,
      totalCredit,
      errors
    })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// GET /api/tenants/:id/adjustments (Landlord or own tenant)
router.get('/tenants/:id/adjustments', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const id = String(req.params.id)
    const user = req.user!
    if (user.role === 'tenant' && user.tenantId !== id && user.userId !== id) {
      return res.status(403).json({ error: 'Access denied to these ledger adjustments.' })
    }
    const items = await db.collection('ledger_adjustments')
      .find({ tenantId: id }, { projection: { _id: 0 } })
      .sort({ createdAt: -1 })
      .toArray()
    res.json(items)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/tenants/:id/adjustments (Landlord only — extra charge like water/garbage/damage OR credit note/waiver)
router.post('/tenants/:id/adjustments', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const id = String(req.params.id)
    const tenant = await db.collection('tenants').findOne({ id })
    if (!tenant) return res.status(404).json({ error: 'Tenant not found.' })

    const { type, amount, category, reason, leaseId, unitNumber } = req.body
    if (!isValidEnum(type, ['charge', 'credit'] as const)) {
      return res.status(400).json({ error: 'Adjustment type must be "charge" or "credit".' })
    }
    const validAmount = parsePositiveAmount(amount)
    if (validAmount === null) {
      return res.status(400).json({ error: 'Adjustment amount must be a valid positive number.' })
    }
    const cleanReason = cleanString(reason, 240)
    if (!cleanReason) {
      return res.status(400).json({ error: 'A clear reason is required for every ledger adjustment.' })
    }
    const cleanCategory = cleanString(category || (type === 'charge' ? 'utility' : 'waiver'), 60)

    let resolvedLeaseId = leaseId ? String(leaseId) : (tenant.currentLeaseId || null)
    let resolvedUnitNumber = unitNumber ? String(unitNumber) : (tenant.currentUnitNumber || '')
    if (resolvedLeaseId) {
      const leaseDoc = await db.collection('leases').findOne({ id: resolvedLeaseId, tenantId: id })
      if (leaseDoc) {
        resolvedUnitNumber = leaseDoc.unitNumber || resolvedUnitNumber
      }
    }

    const nowIso = new Date().toISOString()
    const adjustment = {
      id: generateHexObjectId(),
      tenantId: id,
      tenantName: tenant.name,
      leaseId: resolvedLeaseId,
      unitNumber: resolvedUnitNumber,
      type,
      category: cleanCategory,
      amount: validAmount,
      reason: cleanReason,
      createdBy: req.user?.name || req.user?.email || 'Admin',
      createdAt: nowIso
    }

    await db.collection('ledger_adjustments').insertOne(adjustment)
    const recResult = await runTenantLedgerReconciliation(id, {
      targetLeaseId: resolvedLeaseId,
      targetUnitNumber: resolvedUnitNumber
    })

    logServerEvent('RECONCILE', `Added ${type} adjustment of KES ${validAmount} for ${tenant.name}: ${cleanReason}`)
    await logAuditEvent({
      actor: req.user,
      action: `ledger.adjustment_${type}`,
      entityType: 'ledger_adjustment',
      entityId: adjustment.id,
      summary: `Posted ${type === 'charge' ? 'Extra Charge' : 'Credit / Waiver'} of KES ${validAmount.toLocaleString()} on ${tenant.name} (Unit ${resolvedUnitNumber || 'N/A'}): ${cleanReason}`,
      meta: { tenantId: id, type, amount: validAmount, category: cleanCategory, reason: cleanReason }
    })

    res.status(201).json({ ok: true, adjustment, reconciliation: recResult })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// DELETE /api/tenants/:id/adjustments/:adjId (Landlord only)
router.delete('/tenants/:id/adjustments/:adjId', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const id = String(req.params.id)
    const adjId = String(req.params.adjId)
    const existing = await db.collection('ledger_adjustments').findOne({ id: adjId, tenantId: id })
    if (!existing) return res.status(404).json({ error: 'Ledger adjustment not found.' })

    await db.collection('ledger_adjustments').deleteOne({ id: adjId, tenantId: id })
    const recResult = await runTenantLedgerReconciliation(id)

    await logAuditEvent({
      actor: req.user,
      action: 'ledger.adjustment_delete',
      entityType: 'ledger_adjustment',
      entityId: adjId,
      summary: `Removed ${existing.type} adjustment of KES ${Number(existing.amount || 0).toLocaleString()} for ${existing.tenantName || id} (${existing.reason})`
    })

    res.json({ ok: true, reconciliation: recResult })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/tenants/:id/reconcile (Landlord or own tenant only)
router.post('/tenants/:id/reconcile', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const id = String(req.params.id)
    const user = req.user!
    if (user.role === 'tenant' && user.tenantId !== id && user.userId !== id) {
      return res.status(403).json({ error: 'Access denied: you can only reconcile your own ledger.' })
    }
    const result = await runTenantLedgerReconciliation(id)
    res.json(result)
  } catch (err: any) {
    logServerEvent('RECONCILE', `Reconciliation error: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

// DELETE /api/tenants/:id (Landlord only)
router.delete('/tenants/:id', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const id = String(req.params.id)

    const tenant = await db.collection('tenants').findOne({ id })
    if (!tenant) return res.status(404).json({ error: 'Tenant not found' })

    if (tenant.currentUnitId) {
      return res.status(400).json({ error: `Cannot delete resident ${tenant.name} while currently assigned to Unit ${tenant.currentUnitNumber}.` })
    }

    const activeLease = await db.collection('leases').findOne({ tenantId: id, status: 'active' })
    if (activeLease) {
      return res.status(400).json({ error: `Cannot delete resident ${tenant.name} with an active lease agreement.` })
    }

    await db.collection('tenants').deleteOne({ id })
    await db.collection('users').deleteOne({ email: tenant.email, role: 'tenant' })
    logServerEvent('TENANTS', `Deleted resident ${tenant.name} (${id}) and access credentials from MongoDB`)
    await logAuditEvent({
      actor: req.user,
      action: 'tenant.delete',
      entityType: 'tenant',
      entityId: id,
      summary: `Deleted resident profile ${tenant.name} (${tenant.email})`
    })
    res.json({ success: true, message: `Resident ${tenant.name} deleted successfully.` })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
