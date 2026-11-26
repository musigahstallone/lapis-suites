import crypto from 'crypto'
import { getDb, isDbConnected } from '../db'
import { APP_BASE_URL, generateHexObjectId, normalizeKenyanPhone } from '../config'
import { logServerEvent } from '../middleware/logger'
import { sendSms } from './sms'
import { getRentDueDay } from './settings'
import { runTenantLedgerReconciliation } from '../routes/tenants'

export interface ReminderRunOptions {
  force?: boolean
  tenantId?: string
  triggeredBy?: string
}

export interface ReminderRunSummary {
  checked: number
  sent: number
  skipped: number
  failed: number
  results: Array<{
    tenantId: string
    tenantName: string
    unitNumber: string
    balance: number
    status: 'sent' | 'skipped' | 'failed'
    reason?: string
    linkId?: string
    shortUrl?: string
    reusedLink?: boolean
  }>
}

function generateUniqueLinkId(): string {
  return crypto.randomBytes(6).toString('base64url')
}

function getNairobiNow(): { year: number; month: number; day: number; hour: number; dateStr: string; billingMonth: string } {
  const nairobiDate = new Date(Date.now() + 3 * 60 * 60 * 1000)
  const year = nairobiDate.getUTCFullYear()
  const month = nairobiDate.getUTCMonth() + 1
  const day = nairobiDate.getUTCDate()
  const hour = nairobiDate.getUTCHours()
  const mm = String(month).padStart(2, '0')
  const dd = String(day).padStart(2, '0')
  return {
    year,
    month,
    day,
    hour,
    dateStr: `${year}-${mm}-${dd}`,
    billingMonth: `${year}-${mm}`
  }
}

function determineReminderStage(dayOfMonth: number, dueDay: number, force: boolean): string | null {
  if (force) return 'manual'
  if (dayOfMonth < dueDay) return null
  const daysPastDue = dayOfMonth - dueDay
  if (daysPastDue === 0) return 'due_day'
  if (daysPastDue >= 3 && daysPastDue < 7) return 'overdue_3d'
  if (daysPastDue >= 7) return 'overdue_7d'
  return null
}

/**
 * Records a partial or full payment against a tenant's active persistent payment link.
 * The link stays open (preserving the exact same `linkId`) until `remainingBalance <= 0`,
 * at which point it is marked `paid` and archived into Pay Links History.
 */
export async function recordPaymentAgainstActiveLink(params: {
  tenantId?: string | null
  paymentLinkId?: string | null
  amount: number
  mpesaReceipt?: string
  transactionId?: string
  checkoutRequestId?: string | null
  remainingBalance: number
}): Promise<void> {
  try {
    if (!isDbConnected()) return
    const db = getDb()
    const nowIso = new Date().toISOString()

    let linkDoc: any = null
    if (params.paymentLinkId) {
      linkDoc = await db.collection('payment_links').findOne({ linkId: params.paymentLinkId })
    }
    if (!linkDoc && params.tenantId) {
      linkDoc = await db.collection('payment_links').findOne(
        { tenantId: params.tenantId, status: { $nin: ['paid', 'expired'] } },
        { sort: { createdAt: -1 } }
      )
    }
    if (!linkDoc) return

    const existingPayments: any[] = Array.isArray(linkDoc.payments) ? linkDoc.payments : []
    const alreadyLogged = existingPayments.some(
      (p) =>
        (params.transactionId && p.transactionId === params.transactionId) ||
        (params.mpesaReceipt && p.mpesaReceipt === params.mpesaReceipt)
    )

    const paymentEntry = {
      amount: Math.round(Number(params.amount || 0)),
      mpesaReceipt: params.mpesaReceipt || '',
      transactionId: params.transactionId || null,
      paidAt: nowIso
    }

    const updatedPayments = alreadyLogged ? existingPayments : [...existingPayments, paymentEntry]
    const totalPaidViaLink = updatedPayments.reduce((sum, p) => sum + Number(p.amount || 0), 0)
    const remaining = Math.max(0, Math.round(Number(params.remainingBalance || 0)))
    const isFullySettled = remaining <= 0

    await db.collection('payment_links').updateOne(
      { _id: linkDoc._id },
      {
        $set: {
          payments: updatedPayments,
          totalPaidViaLink,
          paidAmount: totalPaidViaLink,
          remainingBalance: remaining,
          currentAmountDue: remaining,
          mpesaReceipt: params.mpesaReceipt || linkDoc.mpesaReceipt || null,
          transactionId: params.transactionId || linkDoc.transactionId || null,
          checkoutRequestId: params.checkoutRequestId || linkDoc.checkoutRequestId || null,
          status: isFullySettled ? 'paid' : 'partial',
          paidAt: isFullySettled ? nowIso : (linkDoc.paidAt || null),
          settledAt: isFullySettled ? nowIso : null,
          updatedAt: nowIso
        }
      }
    )

    logServerEvent(
      'PAY-LINK',
      `Updated link ${linkDoc.linkId}: +KES ${paymentEntry.amount.toLocaleString()} (totalPaid=KES ${totalPaidViaLink.toLocaleString()}, remaining=KES ${remaining.toLocaleString()}, status=${isFullySettled ? 'paid' : 'partial'})`
    )
  } catch (err: any) {
    logServerEvent('PAY-LINK', `Warning updating payment link after payment: ${err.message}`)
  }
}

/**
 * Evaluates active tenants with unpaid rent / arrears once the payment date is reached.
 * - Reuses the tenant's existing active `linkId` if they have not yet cleared their arrears
 *   (even across month rollovers, joining accumulated arrears onto the same link).
 * - Only mints a brand-new `linkId` after the tenant's previous link was fully settled (`paid`).
 */
export async function checkAndSendDueReminders(options: ReminderRunOptions = {}): Promise<ReminderRunSummary> {
  const summary: ReminderRunSummary = { checked: 0, sent: 0, skipped: 0, failed: 0, results: [] }
  if (!isDbConnected()) return summary

  const db = getDb()
  const force = Boolean(options.force)
  const nairobi = getNairobiNow()

  if (!force && (nairobi.hour < 8 || nairobi.hour >= 19)) {
    return summary
  }

  const leaseQuery: any = { status: { $in: ['active', 'pending_deposit'] } }
  if (options.tenantId) {
    leaseQuery.tenantId = options.tenantId
  }

  const activeLeases = await db.collection('leases').find(leaseQuery).toArray()
  const processedTenants = new Set<string>()
  const configuredDueDay = await getRentDueDay()

  for (const lease of activeLeases) {
    const tenantId = lease.tenantId
    if (!tenantId || processedTenants.has(tenantId)) continue
    processedTenants.add(tenantId)
    summary.checked++

    try {
      const rec = await runTenantLedgerReconciliation(tenantId)
      const tenant = rec.tenant
      const balance = Math.round(Number(rec.summary?.balance || tenant?.balance || 0))
      const unitNumber = tenant?.currentUnitNumber || lease.unitNumber || ''
      const tenantName = tenant?.name || lease.tenantName || 'Resident'
      const normalizedPhone = normalizeKenyanPhone(tenant?.phone || '')

      if (balance <= 0) {
        // Close any leftover active link if the tenant's balance is now zero
        await db.collection('payment_links').updateMany(
          { tenantId, status: { $nin: ['paid', 'expired'] } },
          { $set: { status: 'paid', remainingBalance: 0, currentAmountDue: 0, settledAt: new Date().toISOString(), updatedAt: new Date().toISOString() } }
        )
        summary.skipped++
        summary.results.push({
          tenantId,
          tenantName,
          unitNumber,
          balance: 0,
          status: 'skipped',
          reason: 'Account settled (no arrears due)'
        })
        continue
      }

      if (!/^254[17]\d{8}$/.test(normalizedPhone)) {
        summary.skipped++
        summary.results.push({
          tenantId,
          tenantName,
          unitNumber,
          balance,
          status: 'skipped',
          reason: 'No valid Kenyan phone number on tenant profile'
        })
        continue
      }

      const dueDateStr = lease.nextPaymentDueDate || tenant?.nextPaymentDueDate || `${nairobi.billingMonth}-${String(configuredDueDay).padStart(2, '0')}`
      const hasReachedDueDate = nairobi.dateStr >= dueDateStr || nairobi.day >= configuredDueDay

      if (!force && !hasReachedDueDate) {
        summary.skipped++
        summary.results.push({
          tenantId,
          tenantName,
          unitNumber,
          balance,
          status: 'skipped',
          reason: `Not yet due (due date ${dueDateStr})`
        })
        continue
      }

      const stage = determineReminderStage(nairobi.day, configuredDueDay, force)
      if (!stage) {
        summary.skipped++
        summary.results.push({
          tenantId,
          tenantName,
          unitNumber,
          balance,
          status: 'skipped',
          reason: 'Outside scheduled reminder milestone window'
        })
        continue
      }

      // Check for an existing ACTIVE (unsettled) payment link for this tenant
      const existingActiveLink = await db.collection('payment_links').findOne(
        { tenantId, status: { $nin: ['paid', 'expired'] } },
        { sort: { createdAt: -1 } }
      )

      // Deduplicate automated reminders per billingMonth + stage
      if (!force && existingActiveLink) {
        const sentStages: string[] = Array.isArray(existingActiveLink.sentStages) ? existingActiveLink.sentStages : []
        const stageKey = `${nairobi.billingMonth}:${stage}`
        if (sentStages.includes(stageKey)) {
          summary.skipped++
          summary.results.push({
            tenantId,
            tenantName,
            unitNumber,
            balance,
            status: 'skipped',
            reason: `Already reminded for stage '${stage}' in ${nairobi.billingMonth}`
          })
          continue
        }
      }

      const nowIso = new Date().toISOString()
      let linkId: string
      let shortUrl: string
      let reusedLink = false

      if (existingActiveLink) {
        // Reuse the EXACT same unique linkId until this tenant finishes paying their balance!
        linkId = existingActiveLink.linkId
        shortUrl = existingActiveLink.shortUrl || `${APP_BASE_URL}/p/${linkId}`
        reusedLink = true

        const existingMonths: string[] = Array.isArray(existingActiveLink.billingMonths)
          ? existingActiveLink.billingMonths
          : [existingActiveLink.billingMonth].filter(Boolean)
        const updatedMonths = existingMonths.includes(nairobi.billingMonth)
          ? existingMonths
          : [...existingMonths, nairobi.billingMonth]

        const existingStages: string[] = Array.isArray(existingActiveLink.sentStages) ? existingActiveLink.sentStages : []
        const stageKey = `${nairobi.billingMonth}:${stage}`
        const updatedStages = existingStages.includes(stageKey) ? existingStages : [...existingStages, stageKey]

        await db.collection('payment_links').updateOne(
          { _id: existingActiveLink._id },
          {
            $set: {
              tenantName,
              tenantPhone: normalizedPhone,
              unitNumber,
              billingMonth: nairobi.billingMonth,
              billingMonths: updatedMonths,
              sentStages: updatedStages,
              amountDueAtSend: balance,
              currentAmountDue: balance,
              remainingBalance: balance,
              dueDate: dueDateStr,
              stage,
              lastRemindedAt: nowIso,
              updatedAt: nowIso
            },
            $inc: { remindersSentCount: 1 }
          }
        )
      } else {
        // Mint a brand-new unique linkId (previous cycle was settled or first-ever link)
        linkId = generateUniqueLinkId()
        shortUrl = `${APP_BASE_URL}/p/${linkId}`

        const linkDoc = {
          id: generateHexObjectId(),
          linkId,
          tenantId,
          leaseId: lease.id,
          unitNumber,
          tenantName,
          tenantPhone: normalizedPhone,
          billingMonth: nairobi.billingMonth,
          billingMonths: [nairobi.billingMonth],
          sentStages: [`${nairobi.billingMonth}:${stage}`],
          amountDueAtSend: balance,
          currentAmountDue: balance,
          remainingBalance: balance,
          totalPaidViaLink: 0,
          payments: [],
          monthlyRent: Number(lease.monthlyRent || 0),
          dueDate: dueDateStr,
          stage,
          triggeredBy: options.triggeredBy || (force ? 'landlord_manual' : 'auto_scheduler'),
          remindersSentCount: 1,
          smsTrackingId: null as string | null,
          smsMessageId: null as string | null,
          smsStatus: 'Pending',
          shortUrl,
          status: 'sent', // sent -> clicked -> verified -> partial -> paid
          clickCount: 0,
          clickedAt: null as string | null,
          lastClickedAt: null as string | null,
          otpRequestedAt: null as string | null,
          otpVerifiedAt: null as string | null,
          paidAt: null as string | null,
          settledAt: null as string | null,
          paidAmount: 0,
          checkoutRequestId: null as string | null,
          mpesaReceipt: null as string | null,
          transactionId: null as string | null,
          lastRemindedAt: nowIso,
          createdAt: nowIso,
          updatedAt: nowIso,
          expiresAt: null // Only closes when balance is fully settled
        }

        await db.collection('payment_links').insertOne(linkDoc)
      }

      const trackingId = `rem-${linkId}-${Date.now().toString(36)}`
      const firstName = String(tenantName).split(' ')[0]
      const overdueLabel = nairobi.day > configuredDueDay ? 'overdue' : 'due'
      const smsText = `Hi ${firstName}, your Lapis Suites rent for Unit ${unitNumber} of KES ${balance.toLocaleString()} is ${overdueLabel}. Pay via M-Pesa here: ${shortUrl}`

      const smsRes = await sendSms({
        phone: normalizedPhone,
        message: smsText,
        trackingId,
        purpose: 'rent_reminder',
        recipientEmail: tenant?.email,
        userId: tenantId,
        meta: { linkId, unitNumber, amountDueAtSend: balance, stage, reusedLink }
      })

      await db.collection('payment_links').updateOne(
        { linkId },
        {
          $set: {
            smsTrackingId: trackingId,
            smsMessageId: smsRes.messageId || null,
            smsStatus: smsRes.ok ? 'Accepted' : (smsRes.configured ? 'Failed' : 'NotConfigured'),
            smsError: smsRes.ok ? null : (smsRes.error || 'SMS dispatch failed'),
            updatedAt: new Date().toISOString()
          }
        }
      )

      await db.collection('notifications').insertOne({
        id: generateHexObjectId(),
        tenantId,
        role: 'tenant',
        type: 'rent_due',
        title: `Rent Reminder: KES ${balance.toLocaleString()} Due`,
        message: `Unit ${unitNumber} has an outstanding balance of KES ${balance.toLocaleString()}. Use your secure M-Pesa pay link to settle.`,
        timestamp: nowIso,
        read: false,
        link: `/pay/${linkId}`
      })

      if (smsRes.ok) {
        summary.sent++
        summary.results.push({
          tenantId,
          tenantName,
          unitNumber,
          balance,
          status: 'sent',
          linkId,
          shortUrl,
          reusedLink
        })
      } else {
        summary.failed++
        summary.results.push({
          tenantId,
          tenantName,
          unitNumber,
          balance,
          status: 'failed',
          reason: smsRes.error || 'SMS send failed (payment link active)',
          linkId,
          shortUrl,
          reusedLink
        })
      }
    } catch (err: any) {
      summary.failed++
      logServerEvent('REMINDERS', `Error evaluating tenant ${tenantId}: ${err.message}`)
    }
  }

  if (summary.sent > 0 || force) {
    logServerEvent('REMINDERS', `Reminder run (${force ? 'manual' : 'scheduled'}): checked=${summary.checked}, sent=${summary.sent}, skipped=${summary.skipped}, failed=${summary.failed}`)
  }

  return summary
}

let schedulerTimer: ReturnType<typeof setInterval> | null = null

export function startReminderScheduler() {
  if (schedulerTimer) return
  logServerEvent('REMINDERS', 'Automated rent reminder scheduler started (due day from DB Settings, interval: 60 min)')

  setTimeout(() => {
    checkAndSendDueReminders({ force: false, triggeredBy: 'auto_scheduler' }).catch((err) => {
      logServerEvent('REMINDERS', `Initial scheduled check warning: ${err.message}`)
    })
  }, 30 * 1000)

  schedulerTimer = setInterval(() => {
    checkAndSendDueReminders({ force: false, triggeredBy: 'auto_scheduler' }).catch((err) => {
      logServerEvent('REMINDERS', `Scheduled check warning: ${err.message}`)
    })
  }, 60 * 60 * 1000)
}
