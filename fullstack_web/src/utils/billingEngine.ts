import type { Tenant, Lease, LedgerAllocation } from '../types'

export interface BillingCalculationResult {
  newBalance: number
  arrearsBalance: number
  accountCredit: number
  nextPaymentDueDate: string
  allocation: LedgerAllocation
}

/**
 * Calculates next payment due date anchored to a specific day of the month (default: 5th).
 * If arrears/move-in are cleared and advance credit exists, advances the due date forward accordingly.
 * Strictly requires 100% of an entire monthly rent cycle to advance additional months.
 */
export function calculateNextDueDate(
  baseDateStr: string,
  rentDueDay: number = 5,
  creditBalance: number = 0,
  monthlyRent: number = 0
): string {
  let year: number
  let month: number // 0-indexed

  if (baseDateStr && baseDateStr.includes('-')) {
    const parts = baseDateStr.split('-').map(Number)
    year = parts[0]
    month = parts[1] - 1
  } else {
    const now = new Date()
    year = now.getFullYear()
    month = now.getMonth()
  }

  // Minimum advance is 1 month ahead when current month is paid
  let monthsToAdvance = 1

  // If there is excess advance credit, compute additional months covered
  // Only advances if credit balance covers 100% of an entire subsequent monthly rent cycle
  if (monthlyRent > 0 && creditBalance >= monthlyRent) {
    const extraMonths = Math.floor(creditBalance / monthlyRent)
    monthsToAdvance += extraMonths
  }

  const targetDate = new Date(year, month + monthsToAdvance, rentDueDay)
  const yyyy = targetDate.getFullYear()
  const mm = String(targetDate.getMonth() + 1).padStart(2, '0')
  const dd = String(rentDueDay).padStart(2, '0')

  return `${yyyy}-${mm}-${dd}`
}

/**
 * Automated Lease Billing Engine:
 * Processes incoming funds against a tenant's active lease obligation.
 * 
 * 1. Move-in obligation: Allocates first toward 1st month's rent, then security deposit.
 * 2. Surplus & Advance Credit: Any payment exceeding total obligation is recorded strictly
 *    as Available Account Credit / Surplus (e.g. KES 16,000), resulting in a negative ledger balance.
 * 3. Next Due Date Calculation: Advances strictly to the property's configured billing day
 *    of the immediately following month (e.g. 2026-12-05). Carrying surplus forward without
 *    jumping multiple months unless surplus covers 100% of an entire subsequent monthly rent cycle.
 */
export function processLeaseBilling(
  tenant: Tenant,
  lease: Lease | null,
  amountPaid: number,
  rentDueDay: number = 5
): BillingCalculationResult {
  const monthlyRent = lease?.monthlyRent || 0
  const depositAmount = lease?.depositAmount || 0
  const firstMonthRent = lease?.firstMonthRent || monthlyRent
  const totalMoveInRequired = lease?.totalMoveInRequired || (firstMonthRent + depositAmount)

  // Determine if this is an initial move-in obligation or standard recurring ledger
  const currentBalance = tenant.balance ?? 0
  const isMoveInPhase = Boolean(
    lease &&
    lease.status === 'active' &&
    (currentBalance >= totalMoveInRequired || (currentBalance <= 0 && (!tenant.moveInDate || tenant.moveInDate >= '2026-11-01')))
  )

  let newBalance = 0
  let arrearsBalance = 0
  let accountCredit = 0
  let arrearsPaid = 0
  let rentPaid = 0
  let firstMonthRentPaid = 0
  let depositPaid = 0

  if (isMoveInPhase) {
    // Initial Move-In Allocation Logic:
    // First allocate toward 1st month's rent, then security deposit
    firstMonthRentPaid = Math.min(amountPaid, firstMonthRent)
    rentPaid = firstMonthRentPaid

    const remainingAfterRent = Math.max(0, amountPaid - firstMonthRentPaid)
    depositPaid = Math.min(remainingAfterRent, depositAmount)

    const totalMoveInCovered = firstMonthRentPaid + depositPaid
    const surplus = amountPaid - totalMoveInCovered

    if (surplus > 0) {
      // Payment exceeds initial obligation: record surplus strictly as available account credit
      accountCredit = surplus
      newBalance = -surplus // Negative ledger balance denotes credit standing
      arrearsBalance = 0
      arrearsPaid = totalMoveInCovered
    } else if (surplus < 0) {
      // Underpaid initial obligation
      accountCredit = 0
      newBalance = Math.abs(surplus)
      arrearsBalance = newBalance
      arrearsPaid = totalMoveInCovered
    } else {
      // Exactly settled initial obligation
      accountCredit = 0
      newBalance = 0
      arrearsBalance = 0
      arrearsPaid = totalMoveInCovered
    }
  } else {
    // Standard recurring billing / existing balance
    newBalance = currentBalance - amountPaid

    if (newBalance > 0) {
      // Partial payment: still in arrears
      arrearsBalance = newBalance
      accountCredit = 0
      arrearsPaid = Math.min(currentBalance > 0 ? currentBalance : amountPaid, amountPaid)
      rentPaid = arrearsPaid
    } else {
      // Fully settled arrears + possible advance credit
      arrearsBalance = 0
      accountCredit = Math.abs(newBalance)
      arrearsPaid = currentBalance > 0 ? currentBalance : 0
      rentPaid = Math.min(amountPaid - arrearsPaid, monthlyRent)
    }
  }

  // Next Due Date Calculation:
  // After covering obligation, next due date advances strictly to configured billing day
  // of immediately following month. Does NOT jump multiple months unless surplus covers >= monthlyRent.
  let nextPaymentDueDate = ''

  if (arrearsBalance === 0) {
    // Base reference date is the lease start date for move-in, or the current due date
    const baseDateStr = isMoveInPhase && lease?.startDate
      ? lease.startDate
      : (tenant.nextPaymentDueDate || lease?.nextPaymentDueDate || new Date().toISOString().slice(0, 10))

    nextPaymentDueDate = calculateNextDueDate(
      baseDateStr,
      rentDueDay,
      accountCredit,
      monthlyRent
    )
  } else {
    // In arrears: due date remains immediate or current
    nextPaymentDueDate = tenant.nextPaymentDueDate || lease?.nextPaymentDueDate || ''
    if (!nextPaymentDueDate) {
      const today = new Date()
      nextPaymentDueDate = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(rentDueDay).padStart(2, '0')}`
    }
  }

  return {
    newBalance,
    arrearsBalance,
    accountCredit,
    nextPaymentDueDate,
    allocation: {
      arrearsPaid,
      rentPaid,
      creditBalance: accountCredit,
      firstMonthRentPaid: firstMonthRentPaid || undefined,
      depositPaid: depositPaid || undefined
    }
  }
}
