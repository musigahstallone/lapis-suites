import crypto from 'crypto'
import { Router, Response } from 'express'
import bcrypt from 'bcryptjs'
import { getDb } from '../db'
import { generateHexObjectId } from '../config'
import { logServerEvent } from '../middleware/logger'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { getRentDueDay } from '../services/settings'

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

// Comprehensive ledger & deposit reconciliation logic
export async function runTenantLedgerReconciliation(id: string) {
  const db = getDb()

  const tenant = await db.collection('tenants').findOne({ id })
  if (!tenant) throw new Error('Tenant not found')

  const lease = await db.collection('leases').findOne({
    tenantId: id,
    status: { $in: ['active', 'pending_deposit', 'pending'] }
  }) || await db.collection('leases').findOne({ tenantId: id })

  const unitNumber = tenant.currentUnitNumber || lease?.unitNumber || ''
  const monthlyRent = Number(lease?.monthlyRent || 0)
  const depositAmount = Number(lease?.depositAmount !== undefined ? lease.depositAmount : monthlyRent)

  // 1. Gather all verified payments for this tenant
  const queryConditions: any[] = [
    { tenantId: id }
  ]
  if (tenant.email) queryConditions.push({ payerEmail: tenant.email })
  if (tenant.phone) {
    const cleanPhone = tenant.phone.replace(/\D/g, '')
    if (cleanPhone.length >= 9) {
      queryConditions.push({ phoneNumber: { $regex: cleanPhone.slice(-9) } })
    }
  }
  if (unitNumber) {
    queryConditions.push({ unitNumber })
    queryConditions.push({ billRefNumber: unitNumber })
  }
  if (lease) {
    queryConditions.push({ leaseId: lease.id })
  }

  const txs = await db.collection('transactions').find({
    $or: queryConditions,
    status: { $in: ['reconciled', 'completed', 'paid'] }
  }).sort({ date: 1, timestamp: 1, _id: 1 }).toArray()

  const totalPaid = txs.reduce((sum, tx) => sum + Number(tx.amount || 0), 0)

  // 2. Calculate elapsed billing months
  let monthsBilled = 1
  const baseStartDate = lease?.startDate || tenant.moveInDate || new Date().toISOString().slice(0, 10)
  const startParts = baseStartDate.split('-').map(Number)
  if (startParts.length === 3) {
    const now = new Date()
    const startYear = startParts[0]
    const startMonth = startParts[1] - 1
    const nowYear = now.getFullYear()
    const nowMonth = now.getMonth()
    const monthDiff = (nowYear - startYear) * 12 + (nowMonth - startMonth)
    monthsBilled = Math.max(1, monthDiff + 1)
  }

  // 3. Contractual Obligation: Deposit + Elapsed Months of Rent
  const totalBilled = depositAmount + (monthsBilled * monthlyRent)

  // 4. Deposit Satisfaction Logic:
  // First money paid goes strictly toward Security Deposit
  const depositPaid = totalPaid >= depositAmount
  const depositStatus = depositPaid ? 'paid' : (totalPaid > 0 ? 'partially_paid' : 'pending')
  const leaseStatus = depositPaid ? 'active' : 'pending_deposit'

  // Update payment allocations & descriptions for transactions:
  let runningPaid = 0
  for (const tx of txs) {
    const prevPaid = runningPaid
    runningPaid += Number(tx.amount || 0)

    let paymentType = 'rent'
    let notes = tx.notes || `Payment for Unit ${unitNumber}`

    if (prevPaid < depositAmount) {
      if (runningPaid <= depositAmount) {
        paymentType = 'deposit'
        notes = `Security Deposit allocation (${tx.reference || 'Ref'}) - Reconciled`
      } else {
        paymentType = 'deposit_and_rent'
        const depositPart = depositAmount - prevPaid
        const rentPart = Number(tx.amount || 0) - depositPart
        notes = `Security Deposit (KES ${depositPart}) + Rent (KES ${rentPart}) - Reconciled`
      }
    } else {
      paymentType = 'rent'
      notes = `Rent payment (${tx.reference || 'Ref'}) - Reconciled`
    }

    await db.collection('transactions').updateOne(
      { _id: tx._id },
      {
        $set: {
          tenantId: id,
          tenantName: tenant.name,
          leaseId: lease?.id || tx.leaseId || null,
          unitNumber: unitNumber || tx.unitNumber,
          status: 'reconciled',
          reconciled: true,
          paymentType,
          notes
        }
      }
    )
  }

  // 5. Compute Net Standing & Dynamic Due Date
  const diff = totalPaid - totalBilled
  let balance = 0
  let arrearsBalance = 0
  let accountCredit = 0

  if (diff > 0) {
    accountCredit = diff
    balance = 0
    arrearsBalance = 0
  } else if (diff < 0) {
    balance = Math.abs(diff)
    arrearsBalance = Math.abs(diff)
    accountCredit = 0
  }

  // Dynamic next payment due date from Settings (MongoDB)
  const rentDueDay = await getRentDueDay()
  let monthsToAdvance = 1
  if (monthlyRent > 0 && accountCredit >= monthlyRent) {
    monthsToAdvance += Math.floor(accountCredit / monthlyRent)
  }
  const targetDate = new Date(startParts[0] || new Date().getFullYear(), (startParts[1] ? startParts[1] - 1 : new Date().getMonth()) + monthsToAdvance, rentDueDay)
  const nextPaymentDueDate = `${targetDate.getFullYear()}-${String(targetDate.getMonth() + 1).padStart(2, '0')}-${String(rentDueDay).padStart(2, '0')}`

  const nowIso = new Date().toISOString()

  // 6. Update Lease Entity in MongoDB
  let updatedLease = null
  if (lease) {
    await db.collection('leases').updateOne(
      { id: lease.id },
      {
        $set: {
          tenantId: id,
          tenantName: tenant.name,
          depositPaid,
          depositStatus,
          status: leaseStatus,
          nextPaymentDueDate,
          updatedAt: nowIso
        }
      }
    )
    updatedLease = await db.collection('leases').findOne({ id: lease.id }, { projection: { _id: 0 } })
  }

  // 7. Update Tenant Record in MongoDB
  await db.collection('tenants').updateOne(
    { id },
    {
      $set: {
        balance,
        arrearsBalance,
        accountCredit,
        nextPaymentDueDate,
        updatedAt: nowIso
      }
    }
  )
  const updatedTenant = await db.collection('tenants').findOne({ id }, { projection: { _id: 0 } })

  logServerEvent('RECONCILE', `Full Ledger Reconciliation completed for ${tenant.name} (Unit ${unitNumber}): Total Paid: KES ${totalPaid}, Billed: KES ${totalBilled}, Deposit Paid: ${depositPaid}, Credit: KES ${accountCredit}, Arrears: KES ${balance}, Next Due: ${nextPaymentDueDate}`)

  return {
    success: true,
    tenant: updatedTenant,
    lease: updatedLease,
    summary: {
      totalPaid,
      totalBilled,
      depositAmount,
      depositPaid,
      monthsBilled,
      accountCredit,
      balance,
      nextPaymentDueDate
    }
  }
}

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
    res.json({ success: true, message: `Resident ${tenant.name} deleted successfully.` })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
