import { Router, Response } from 'express'
import { getDb } from '../db'
import { generateHexObjectId } from '../config'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { logServerEvent } from '../middleware/logger'
import { broadcastServerEvent } from '../events'
import { runTenantLedgerReconciliation } from './tenants'
import { notifyTenantSms } from '../services/sms'
import { recordPaymentAgainstActiveLink } from '../services/reminders'

const router = Router()

// GET /api/transactions (Landlord sees all; Tenant sees ONLY their own transactions)
router.get('/transactions', authenticateToken, async (req: AuthRequest, res: Response) => {
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
    } else {
      if (req.query.tenantId) query.tenantId = String(req.query.tenantId)
      if (req.query.unitNumber) query.unitNumber = String(req.query.unitNumber)
    }

    const transactions = await db.collection('transactions')
      .find(query, { projection: { _id: 0 } })
      .sort({ date: -1, timestamp: -1 })
      .toArray()

    logServerEvent('PAYMENTS', `Loaded ${transactions.length} transactions for ${user.role}`)
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

    const numericAmount = Number(amount)
    if (!Number.isFinite(numericAmount) || numericAmount <= 0 || numericAmount > 10000000) {
      return res.status(400).json({ error: 'Valid positive amount is required.' })
    }

    // Tenant submissions MUST include a real M-Pesa transaction code and can ONLY apply to their own account
    const rawRef = reference ? String(reference).trim().toUpperCase() : ''
    if (!isLandlord && rawRef.length < 5) {
      return res.status(400).json({ error: 'A valid M-Pesa transaction code (at least 5 characters) is required for manual Paybill verification.' })
    }

    const effectiveTenantIdInput = isLandlord ? reqTenantId : (user.tenantId || user.userId)
    const effectiveUnitInput = isLandlord ? reqUnitNumber : (user.unitNumber || '')

    let tenant: any = null
    let lease: any = null

    if (isLandlord && reqLeaseId) {
      lease = await db.collection('leases').findOne({ id: String(reqLeaseId) })
      if (lease) {
        tenant = await db.collection('tenants').findOne({ id: lease.tenantId })
      }
    }
    if (!tenant && effectiveTenantIdInput) {
      tenant = await db.collection('tenants').findOne({ id: String(effectiveTenantIdInput) })
    }
    if (!tenant && effectiveUnitInput) {
      tenant = await db.collection('tenants').findOne({ currentUnitNumber: String(effectiveUnitInput).trim() })
    }
    if (!tenant && !isLandlord && user.email) {
      tenant = await db.collection('tenants').findOne({ email: user.email.toLowerCase() })
    }
    if (tenant && !lease) {
      lease = await db.collection('leases').findOne({
        tenantId: tenant.id,
        status: { $in: ['active', 'pending_deposit'] }
      }) || await db.collection('leases').findOne({ tenantId: tenant.id })
    }

    const effectiveUnitNumber = (isLandlord ? reqUnitNumber : '') || tenant?.currentUnitNumber || lease?.unitNumber || user.unitNumber || ''
    const effectiveUnitId = tenant?.currentUnitId || lease?.unitId || null
    const effectiveLeaseId = (isLandlord ? reqLeaseId : null) || tenant?.currentLeaseId || lease?.id || null

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
    await db.collection('transactions').insertOne(newTx)
    logServerEvent('PAYMENTS', `Recorded ${txStatus} payment: KES ${newTx.amount.toLocaleString()} for Unit ${newTx.unitNumber} [Ref: ${ref}, by: ${user.role}]`)

    // Only credit balance & update payment links if verified (Landlord entry)
    let updatedLease = lease
    let recSummary: any = null
    if (isLandlord && newTx.tenantId) {
      try {
        const recResult = await runTenantLedgerReconciliation(newTx.tenantId)
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

    const nowIso = new Date().toISOString()
    const result = await db.collection('transactions').findOneAndUpdate(
      { id: String(transactionId) },
      {
        $set: {
          tenantId: tenant.id,
          tenantName: tenant.name,
          unitId: unit ? unit.id : tenant.currentUnitId,
          unitNumber: unit ? unit.unitNumber : tenant.currentUnitNumber,
          leaseId: tenant.currentLeaseId,
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
        const recRes = await runTenantLedgerReconciliation(tenant.id)
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
    res.json(result)
  } catch (err: any) {
    res.status(500).json({ error: err.message })
  }
})

export default router
