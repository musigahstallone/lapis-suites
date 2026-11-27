import { Router, Response } from 'express'
import { getDb } from '../db'
import { generateHexObjectId } from '../config'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { logServerEvent } from '../middleware/logger'
import { broadcastServerEvent } from '../events'
import { runTenantLedgerReconciliation } from './tenants'
import { notifyTenantSms } from '../services/sms'
import { recordPaymentAgainstActiveLink } from '../services/reminders'
import { logAuditEvent } from '../services/audit'
import { parsePositiveAmount, isIsoDate, cleanString } from '../middleware/validate'

const router = Router()

// GET /api/transactions (Landlord sees all; Tenant sees ONLY their own transactions; supports ?page, ?limit, ?search, ?status)
router.get('/transactions', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    const conditions: any[] = []

    if (user.role === 'tenant') {
      const orClauses: any[] = []
      if (user.tenantId) orClauses.push({ tenantId: user.tenantId })
      if (user.userId) orClauses.push({ tenantId: user.userId })
      if (orClauses.length === 0) {
        res.setHeader('X-Total-Count', '0')
        return res.json([])
      }
      conditions.push({ $or: orClauses })
    } else {
      if (req.query.tenantId) conditions.push({ tenantId: String(req.query.tenantId) })
      if (req.query.unitNumber) conditions.push({ unitNumber: String(req.query.unitNumber) })
    }

    if (req.query.status && req.query.status !== 'all') {
      conditions.push({ status: String(req.query.status) })
    }

    const search = cleanString(req.query.search, 120)
    if (search) {
      const escaped = search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      const regex = new RegExp(escaped, 'i')
      conditions.push({
        $or: [
          { reference: regex },
          { tenantName: regex },
          { unitNumber: regex },
          { phoneNumber: regex },
          { payerName: regex }
        ]
      })
    }

    const query = conditions.length === 0 ? {} : (conditions.length === 1 ? conditions[0] : { $and: conditions })

    const rawPage = req.query.page ? Number(req.query.page) : 0
    const rawLimit = req.query.limit ? Number(req.query.limit) : 0
    const hasPagination = (Number.isFinite(rawPage) && rawPage > 0) || (Number.isFinite(rawLimit) && rawLimit > 0)

    const total = await db.collection('transactions').countDocuments(query)
    res.setHeader('X-Total-Count', String(total))

    let cursor = db.collection('transactions')
      .find(query, { projection: { _id: 0 } })
      .sort({ date: -1, timestamp: -1 })

    if (hasPagination) {
      const page = Math.max(1, Number.isFinite(rawPage) && rawPage > 0 ? Math.floor(rawPage) : 1)
      const limit = Math.min(200, Math.max(1, Number.isFinite(rawLimit) && rawLimit > 0 ? Math.floor(rawLimit) : 50))
      cursor = cursor.skip((page - 1) * limit).limit(limit)
    }

    const transactions = await cursor.toArray()

    logServerEvent('PAYMENTS', `Loaded ${transactions.length}/${total} transactions for ${user.role}`)
    res.json(transactions)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// GET /api/transactions/:id (Landlord sees any; Tenant sees ONLY their own)
router.get('/transactions/:id', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    const tx = await db.collection('transactions').findOne({ id: String(req.params.id) }, { projection: { _id: 0 } })
    if (!tx) return res.status(404).json({ error: 'Transaction not found' })

    if (user.role === 'tenant') {
      const isOwn =
        (user.tenantId && tx.tenantId === user.tenantId) ||
        (user.userId && tx.tenantId === user.userId) ||
        (user.unitNumber && tx.unitNumber === user.unitNumber)
      if (!isOwn) {
        return res.status(403).json({ error: 'Access denied to this transaction.' })
      }
    }

    res.json(tx)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/transactions (Authenticated: Landlord records reconciled payment; Tenant manual Paybill claim awaits verification)
router.post('/transactions', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const user = req.user!
    const isLandlord = user.role === 'landlord'
    const {
      tenantId: reqTenantId,
      unitNumber: reqUnitNumber,
      amount,
      method,
      category,
      date,
      notes,
      reference,
      leaseId: reqLeaseId,
      phoneNumber: reqPhone,
      payerName: reqPayerName
    } = req.body

    const numericAmount = parsePositiveAmount(amount)
    if (numericAmount === null) {
      return res.status(400).json({ error: 'Valid positive amount is required.' })
    }
    if (isLandlord && date && !isIsoDate(date)) {
      return res.status(400).json({ error: 'Payment date must be a valid YYYY-MM-DD date.' })
    }

    // Tenant submissions MUST include a real M-Pesa transaction code and can ONLY apply to their own account
    const rawRef = reference ? cleanString(reference, 64).toUpperCase() : ''
    if (!isLandlord && rawRef.length < 5) {
      return res.status(400).json({ error: 'A valid M-Pesa transaction code (at least 5 characters) is required for manual Paybill verification.' })
    }

    const effectiveTenantIdInput = isLandlord ? reqTenantId : (user.tenantId || user.userId)
    const effectiveUnitInput = isLandlord ? reqUnitNumber : (user.unitNumber || '')

    let tenant: any = null
    let lease: any = null

    if (effectiveTenantIdInput) {
      tenant = await db.collection('tenants').findOne({ id: String(effectiveTenantIdInput) })
    }
    if (!tenant && !isLandlord && user.email) {
      tenant = await db.collection('tenants').findOne({ email: user.email.toLowerCase() })
    }

    // Resolve lease strictly: landlord can pick any leaseId/unit; tenant can pick ANY of their OWN active leases (supports multi-unit residents!)
    if (reqLeaseId) {
      const candidateLease = await db.collection('leases').findOne({ id: String(reqLeaseId) })
      if (candidateLease) {
        if (isLandlord) {
          lease = candidateLease
          if (!tenant) tenant = await db.collection('tenants').findOne({ id: candidateLease.tenantId })
        } else if (tenant && candidateLease.tenantId === tenant.id) {
          lease = candidateLease
        }
      }
    }
    if (!lease && reqUnitNumber) {
      const unitFilter: any = {
        unitNumber: String(reqUnitNumber).trim(),
        status: { $in: ['active', 'pending_deposit'] }
      }
      if (!isLandlord && tenant) unitFilter.tenantId = tenant.id
      lease = await db.collection('leases').findOne(unitFilter)
      if (lease && !tenant && isLandlord) {
        tenant = await db.collection('tenants').findOne({ id: lease.tenantId })
      }
    }
    if (!tenant && effectiveUnitInput) {
      tenant = await db.collection('tenants').findOne({ currentUnitNumber: String(effectiveUnitInput).trim() })
    }
    if (tenant && !lease) {
      lease = await db.collection('leases').findOne(
        {
          tenantId: tenant.id,
          status: { $in: ['active', 'pending_deposit'] }
        },
        { sort: { startDate: 1, createdAt: 1 } }
      ) || await db.collection('leases').findOne({ tenantId: tenant.id })
    }

    const effectiveUnitNumber = lease?.unitNumber || (isLandlord ? reqUnitNumber : '') || tenant?.currentUnitNumber || user.unitNumber || ''
    const effectiveUnitId = lease?.unitId || tenant?.currentUnitId || null
    const effectiveLeaseId = lease?.id || (isLandlord ? reqLeaseId : null) || tenant?.currentLeaseId || null

    if (isLandlord && tenant && (!tenant.currentUnitNumber || !tenant.currentUnitId) && (effectiveUnitNumber || effectiveUnitId)) {
      await db.collection('tenants').updateOne(
        { id: tenant.id },
        { $set: { currentUnitId: effectiveUnitId, currentUnitNumber: effectiveUnitNumber, currentLeaseId: effectiveLeaseId } }
      )
    }

    const nowIso = new Date().toISOString()
    const ref = rawRef || `MP-${Date.now().toString().slice(-6)}`

    // Check duplicate reference
    const existingTx = await db.collection('transactions').findOne({ reference: ref }, { projection: { _id: 0 } })
    if (existingTx) {
      if (!isLandlord && existingTx.tenantId !== tenant?.id) {
        return res.status(409).json({ error: `Transaction reference ${ref} has already been recorded.` })
      }
      logServerEvent('PAYMENTS', `Transaction reference ${ref} already exists. Returning existing transaction.`)
      return res.json(existingTx)
    }

    // Security rule: Tenant-submitted manual Paybill references MUST be verified by management before crediting rent balances
    const txStatus = isLandlord ? 'reconciled' : 'pending_verification'
    const txReconciled = isLandlord

    const newTx = {
      id: generateHexObjectId(),
      reference: ref,
      invoiceRef: `INV-${Date.now().toString().slice(-5)}`,
      tenantId: tenant ? tenant.id : null,
      tenantName: tenant ? tenant.name : (reqPayerName || user.name || 'Direct Resident'),
      unitId: effectiveUnitId,
      unitNumber: effectiveUnitNumber,
      leaseId: effectiveLeaseId,
      amount: numericAmount,
      date: (isLandlord && date) ? String(date) : nowIso.slice(0, 10),
      timestamp: (isLandlord && date) ? `${date} 12:00:00` : nowIso.replace('T', ' ').slice(0, 19),
      method: method === 'stk_push' ? 'stk_push' : 'mpesa_paybill',
      source: req.body.source || 'manual',
      paymentType: req.body.paymentType || 'deposit_and_rent',
      status: txStatus,
      category: category || 'rent',
      phoneNumber: reqPhone || tenant?.phone || user.phone || '',
      payerName: reqPayerName || tenant?.name || user.name || 'Resident',
      billRefNumber: effectiveUnitNumber,
      notes: notes ? String(notes).trim() : (isLandlord ? `M-Pesa payment for Unit ${effectiveUnitNumber || 'Suite'}` : `Resident Paybill claim (Ref: ${ref}) — awaiting management verification`),
      reconciled: txReconciled,
      reconciledAt: txReconciled ? nowIso : null,
      reconciledBy: txReconciled ? (req.body.reconciledBy || `${user.name} (Manual Entry)`) : null,
      submittedByRole: user.role
    }
    try {
      await db.collection('transactions').insertOne(newTx)
    } catch (dupErr: any) {
      if (dupErr?.code === 11000) {
        const dupTx = await db.collection('transactions').findOne({ reference: ref }, { projection: { _id: 0 } })
        if (!isLandlord && dupTx && dupTx.tenantId !== tenant?.id) {
          return res.status(409).json({ error: `Transaction reference ${ref} has already been recorded.` })
        }
        return res.json(dupTx || { error: `Duplicate reference ${ref}` })
      }
      throw dupErr
    }
    logServerEvent('PAYMENTS', `Recorded ${txStatus} payment: KES ${newTx.amount.toLocaleString()} for Unit ${newTx.unitNumber} [Ref: ${ref}, by: ${user.role}]`)
    await logAuditEvent({
      actor: req.user,
      action: isLandlord ? 'payment.record' : 'payment.claim',
      entityType: 'transaction',
      entityId: newTx.id,
      summary: `${isLandlord ? 'Recorded' : 'Submitted claim for'} KES ${newTx.amount.toLocaleString()} for ${newTx.tenantName} (Unit ${newTx.unitNumber || 'N/A'}, Ref: ${ref})`,
      meta: { amount: newTx.amount, reference: ref, status: txStatus, unitNumber: newTx.unitNumber }
    })

    // Only credit balance & update payment links if verified (Landlord entry)
    let updatedLease = lease
    let recSummary: any = null
    if (isLandlord && newTx.tenantId) {
      try {
        const recResult = await runTenantLedgerReconciliation(newTx.tenantId, {
          targetLeaseId: newTx.leaseId,
          targetUnitNumber: newTx.unitNumber
        })
        if (recResult.lease) updatedLease = recResult.lease
        recSummary = recResult.summary
        await recordPaymentAgainstActiveLink({
          tenantId: newTx.tenantId,
          amount: newTx.amount,
          mpesaReceipt: newTx.reference,
          transactionId: newTx.id,
          remainingBalance: Number(recSummary?.balance || 0)
        })
      } catch (err: any) {
        logServerEvent('PAYMENTS', `Automatic reconciliation notice: ${err.message}`)
      }
    }

    // Create automated in-app notifications
    const notifLandlord = {
      id: generateHexObjectId(),
      role: 'landlord',
      type: 'payment_received',
      title: isLandlord
        ? `Payment Received: KES ${newTx.amount.toLocaleString()}`
        : `Verify Manual Paybill: KES ${newTx.amount.toLocaleString()}`,
      message: isLandlord
        ? `${newTx.tenantName} paid KES ${newTx.amount.toLocaleString()} for Unit ${newTx.unitNumber} via ${newTx.method} (Ref: ${newTx.reference}).`
        : `${newTx.tenantName} (Unit ${newTx.unitNumber}) submitted M-Pesa Ref ${newTx.reference} for KES ${newTx.amount.toLocaleString()}. Review in Reconciliation to verify and credit.`,
      timestamp: nowIso,
      read: false,
      link: isLandlord ? '/payments' : '/reconciliation'
    }
    await db.collection('notifications').insertOne(notifLandlord)

    let notifTenant: any = null
    if (newTx.tenantId) {
      notifTenant = {
        id: generateHexObjectId(),
        tenantId: newTx.tenantId,
        role: 'tenant',
        type: 'payment_confirmed',
        title: isLandlord
          ? `Payment Acknowledged: KES ${newTx.amount.toLocaleString()}`
          : `Payment Submitted for Verification`,
        message: isLandlord
          ? `Your payment of KES ${newTx.amount.toLocaleString()} for Unit ${newTx.unitNumber} has been received and recorded. Ref: ${newTx.reference}.`
          : `Your manual Paybill reference ${newTx.reference} (KES ${newTx.amount.toLocaleString()}) has been logged and is awaiting management verification.`,
        timestamp: nowIso,
        read: false,
        link: '/tenant/payments'
      }
      await db.collection('notifications').insertOne(notifTenant)
    }

    // Landlord manual entry: SMS the tenant only (never SMS landlord on manual entry)
    if (isLandlord) {
      const tenantPhone = tenant?.phone || newTx.phoneNumber
      if (tenantPhone) {
        let standingText = ''
        if (recSummary) {
          if (recSummary.balance > 0) {
            standingText = ` Remaining balance: KES ${Math.round(recSummary.balance).toLocaleString()}.`
          } else if (recSummary.accountCredit > 0) {
            standingText = ` Account credit: KES ${Math.round(recSummary.accountCredit).toLocaleString()}.`
          } else {
            standingText = ' Your rent account is settled.'
          }
        }
        const firstName = String(newTx.tenantName || 'Resident').split(' ')[0]
        const tenantSms = `Hi ${firstName}, Lapis Suites has received your rent payment of KES ${newTx.amount.toLocaleString()} for Unit ${newTx.unitNumber || 'Suite'} (Ref: ${newTx.reference}).${standingText} Thank you.`
        notifyTenantSms(tenantPhone, tenantSms, 'payment_receipt', {
          recipientEmail: tenant?.email,
          userId: newTx.tenantId || undefined,
          meta: { transactionId: newTx.id, reference: newTx.reference, source: newTx.source }
        })
      }
    }

    // Real-time broadcast
    broadcastServerEvent('payment_received', { transaction: newTx, lease: updatedLease })
    broadcastServerEvent('notification', notifLandlord)
    if (notifTenant) broadcastServerEvent('notification', notifTenant)

    res.status(201).json({ ...newTx, pendingVerification: !isLandlord })
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/transactions/reconcile (Landlord only — approves unassigned OR pending_verification claims)
router.post('/transactions/reconcile', authenticateToken, requireRole(['landlord']), async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { transactionId, tenantId, unitId, notes } = req.body
    const tenant = await db.collection('tenants').findOne({ id: String(tenantId) })
    const unit = unitId ? await db.collection('units').findOne({ id: String(unitId) }) : null
    if (!tenant) return res.status(404).json({ error: 'Tenant not found' })

    // Resolve matching lease for multi-unit tenants (unit match -> first active lease)
    const activeLeases = await db.collection('leases')
      .find({ tenantId: tenant.id, status: { $in: ['active', 'pending_deposit'] } })
      .sort({ startDate: 1, createdAt: 1 })
      .toArray()
    const matchedLease =
      (unit ? activeLeases.find((l: any) => l.unitId === unit.id || l.unitNumber === unit.unitNumber) : null) ||
      activeLeases[0] ||
      null

    const resolvedUnitId = unit ? unit.id : (matchedLease?.unitId || tenant.currentUnitId || null)
    const resolvedUnitNumber = unit ? unit.unitNumber : (matchedLease?.unitNumber || tenant.currentUnitNumber || '')
    const resolvedLeaseId = matchedLease?.id || tenant.currentLeaseId || null

    const nowIso = new Date().toISOString()
    const result = await db.collection('transactions').findOneAndUpdate(
      { id: String(transactionId) },
      {
        $set: {
          tenantId: tenant.id,
          tenantName: tenant.name,
          unitId: resolvedUnitId,
          unitNumber: resolvedUnitNumber,
          leaseId: resolvedLeaseId,
          status: 'reconciled',
          reconciled: true,
          reconciledAt: nowIso,
          reconciledBy: `${req.user?.name || 'Admin'} (Manual Reconciliation)`,
          notes: notes ? String(notes).trim() : 'Verified and reconciled to resident ledger'
        }
      },
      { returnDocument: 'after', projection: { _id: 0 } }
    )

    if (result) {
      let recSummary: any = null
      try {
        const recRes = await runTenantLedgerReconciliation(tenant.id, {
          targetLeaseId: resolvedLeaseId,
          targetUnitNumber: resolvedUnitNumber
        })
        recSummary = recRes.summary
        await recordPaymentAgainstActiveLink({
          tenantId: tenant.id,
          amount: Number(result.amount || 0),
          mpesaReceipt: result.reference,
          transactionId: result.id,
          remainingBalance: Number(recSummary?.balance || 0)
        })
      } catch {}

      const notifTenant = {
        id: generateHexObjectId(),
        tenantId: tenant.id,
        role: 'tenant',
        type: 'payment_confirmed',
        title: `Payment Reconciled: KES ${Number(result.amount || 0).toLocaleString()}`,
        message: `Payment of KES ${Number(result.amount || 0).toLocaleString()} (Ref: ${result.reference}) has been verified and applied to your account balance.`,
        timestamp: nowIso,
        read: false,
        link: '/tenant/payments'
      }
      await db.collection('notifications').insertOne(notifTenant)
      broadcastServerEvent('notification', notifTenant)

      // Manual reconciliation: ONLY SMS the tenant (do NOT SMS landlord)
      const tenantPhone = tenant.phone || result.phoneNumber
      if (tenantPhone) {
        const balanceNote = recSummary?.balance > 0
          ? ` Remaining balance: KES ${Math.round(recSummary.balance).toLocaleString()}.`
          : ' Your account is up to date.'
        const firstName = String(tenant.name || 'Resident').split(' ')[0]
        notifyTenantSms(
          tenantPhone,
          `Hi ${firstName}, your payment of KES ${Number(result.amount || 0).toLocaleString()} (Ref: ${result.reference}) for Unit ${result.unitNumber || tenant.currentUnitNumber || 'Suite'} has been verified and reconciled.${balanceNote}`,
          'payment_receipt',
          { recipientEmail: tenant.email, userId: tenant.id, meta: { transactionId: result.id, reference: result.reference } }
        )
      }
    }

    logServerEvent('PAYMENTS', `Reconciled transaction ${transactionId} to ${tenant.name} in MongoDB`)
    await logAuditEvent({
      actor: req.user,
      action: 'payment.reconcile',
      entityType: 'transaction',
      entityId: String(transactionId),
      summary: `Reconciled payment ${result?.reference || transactionId} (KES ${Number(result?.amount || 0).toLocaleString()}) to ${tenant.name} (Unit ${resolvedUnitNumber || 'N/A'})`
    })
    res.json(result)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
