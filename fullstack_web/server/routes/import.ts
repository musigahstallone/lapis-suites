import { Router, Request, Response } from 'express'
import { getDb } from '../db'
import { generateHexObjectId } from '../config'
import { authenticateToken, requireRole, AuthRequest } from '../middleware/auth'
import { logServerEvent } from '../middleware/logger'

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

const router = Router()

// Protected by Landlord Role
router.use(authenticateToken)
router.use(requireRole(['landlord']))

// POST /api/import/units
router.post('/import/units', async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { units } = req.body

    if (!Array.isArray(units) || units.length === 0) {
      return res.status(400).json({ error: 'Array of units is required for import.' })
    }

    let imported = 0
    let skipped = 0
    const nowIso = new Date().toISOString()

    for (const u of units) {
      const cleanNum = String(u.unitNumber || '').trim().toUpperCase()
      if (!cleanNum) {
        skipped++
        continue
      }

      const existing = await db.collection('units').findOne({ unitNumber: cleanNum })
      if (existing) {
        skipped++
        continue
      }

      const doc = {
        id: generateHexObjectId(),
        unitNumber: cleanNum,
        type: u.type || 'studio',
        status: u.status || 'vacant',
        currentTenantId: null,
        currentLeaseId: null,
        createdAt: nowIso
      }
      await db.collection('units').insertOne(doc)
      imported++
    }

    logServerEvent('IMPORT', `Bulk imported units: ${imported} added, ${skipped} skipped`)
    res.json({ success: true, imported, skipped, total: units.length })
  } catch (err: any) {
    logServerEvent('IMPORT', `Error importing units: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

// POST /api/import/tenants-leases
router.post('/import/tenants-leases', async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { records } = req.body

    if (!Array.isArray(records) || records.length === 0) {
      return res.status(400).json({ error: 'Array of resident records is required.' })
    }

    let importedTenants = 0
    let importedLeases = 0
    let skipped = 0
    const nowIso = new Date().toISOString()

    for (const r of records) {
      const name = String(r.name || '').trim()
      const email = String(r.email || '').trim().toLowerCase()
      if (!name || !email) {
        skipped++
        continue
      }

      let tenant = await db.collection('tenants').findOne({ email })
      const initials = name.split(' ').map((p: string) => p[0]).join('').slice(0, 2).toUpperCase() || 'TN'

      let tenantId = tenant ? tenant.id : generateHexObjectId()

      if (!tenant) {
        tenant = {
          id: tenantId,
          name,
          email,
          phone: String(r.phone || '').trim(),
          nationalId: r.nationalId ? String(r.nationalId).trim() : 'ID-MIGRATED',
          currentUnitId: null,
          currentUnitNumber: '',
          currentLeaseId: null,
          balance: 0,
          arrearsBalance: 0,
          accountCredit: 0,
          nextPaymentDueDate: computeNextPaymentDueDate(r.startDate),
          status: 'active',
          moveInDate: r.startDate || nowIso.slice(0, 10),
          avatarInitials: initials,
          createdAt: nowIso
        }
        await db.collection('tenants').insertOne(tenant)
        importedTenants++
      }

      // If unit number is specified, assign lease and occupy unit
      const unitNum = String(r.unitNumber || '').trim().toUpperCase()
      if (unitNum) {
        const unit = await db.collection('units').findOne({ unitNumber: unitNum })
        if (unit) {
          const leaseId = generateHexObjectId()
          const leaseNumber = `LPS-L${Math.floor(1000 + Math.random() * 9000)}`
          const rent = Number(r.monthlyRent || 0)
          const deposit = Number(r.depositAmount || rent)
          const depositPaid = Boolean(r.depositPaid !== false)

          const oneYearLater = new Date()
          oneYearLater.setFullYear(oneYearLater.getFullYear() + 1)

          const newLease = {
            id: leaseId,
            leaseNumber,
            tenantId,
            tenantName: name,
            unitId: unit.id,
            unitNumber: unit.unitNumber,
            unitType: unit.type,
            startDate: r.startDate || nowIso.slice(0, 10),
            endDate: r.endDate || oneYearLater.toISOString().slice(0, 10),
            monthlyRent: rent,
            depositAmount: deposit,
            depositPaid,
            status: 'active',
            terms: 'Historical imported tenancy agreement.',
            nextPaymentDueDate: computeNextPaymentDueDate(r.startDate),
            createdAt: nowIso
          }

          await db.collection('leases').insertOne(newLease)
          await db.collection('units').updateOne(
            { id: unit.id },
            { $set: { status: 'occupied', currentTenantId: tenantId, currentLeaseId: leaseId, updatedAt: nowIso } }
          )
          await db.collection('tenants').updateOne(
            { id: tenantId },
            { $set: { currentUnitId: unit.id, currentUnitNumber: unit.unitNumber, currentLeaseId: leaseId, updatedAt: nowIso } }
          )
          importedLeases++
        }
      }
    }

    logServerEvent('IMPORT', `Bulk imported records: ${importedTenants} residents added, ${importedLeases} leases created, ${skipped} skipped`)
    res.json({ success: true, importedTenants, importedLeases, skipped, total: records.length })
  } catch (err: any) {
    logServerEvent('IMPORT', `Error importing records: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

// POST /api/import/transactions
router.post('/import/transactions', async (req: AuthRequest, res: Response) => {
  try {
    const db = getDb()
    const { transactions } = req.body

    if (!Array.isArray(transactions) || transactions.length === 0) {
      return res.status(400).json({ error: 'Array of transaction records is required.' })
    }

    let imported = 0
    let skipped = 0
    const nowIso = new Date().toISOString()

    for (const t of transactions) {
      const ref = String(t.reference || '').trim().toUpperCase()
      const amt = Number(t.amount || 0)
      if (!ref || amt <= 0) {
        skipped++
        continue
      }

      const existing = await db.collection('transactions').findOne({ reference: ref })
      if (existing) {
        skipped++
        continue
      }

      const unitNum = String(t.unitNumber || '').trim().toUpperCase()
      let tenant = null
      let unit = null
      if (unitNum) {
        unit = await db.collection('units').findOne({ unitNumber: unitNum })
        if (unit?.currentTenantId) {
          tenant = await db.collection('tenants').findOne({ id: unit.currentTenantId })
        }
      }

      const doc = {
        id: generateHexObjectId(),
        reference: ref,
        invoiceRef: `INV-${Date.now().toString().slice(-5)}`,
        tenantId: tenant ? tenant.id : null,
        tenantName: tenant ? tenant.name : String(t.tenantName || 'Historical Resident').trim(),
        unitId: unit ? unit.id : null,
        unitNumber: unitNum || 'HISTORICAL',
        leaseId: tenant ? tenant.currentLeaseId : null,
        amount: amt,
        date: t.date || nowIso.slice(0, 10),
        timestamp: `${t.date || nowIso.slice(0, 10)} 12:00:00`,
        method: t.method || 'mpesa_paybill',
        status: 'reconciled',
        category: 'rent',
        phoneNumber: tenant?.phone || '',
        payerName: tenant ? tenant.name : String(t.tenantName || 'Historical Remitter').trim(),
        billRefNumber: unitNum || '',
        notes: t.notes || 'Historical imported payment ledger entry',
        reconciled: true,
        reconciledAt: nowIso,
        reconciledBy: 'Staff Historical Import'
      }

      await db.collection('transactions').insertOne(doc)
      imported++
    }

    logServerEvent('IMPORT', `Bulk imported historical transactions: ${imported} added, ${skipped} skipped`)
    res.json({ success: true, imported, skipped, total: transactions.length })
  } catch (err: any) {
    logServerEvent('IMPORT', `Error importing transactions: ${err.message}`)
    res.status(500).json({ error: err.message })
  }
})

export default router
