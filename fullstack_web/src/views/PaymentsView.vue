<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import {
  CreditCard,
  Plus,
  Search,
  Filter,
  RefreshCw,
  Smartphone,
  ShieldCheck,
  ChevronRight,
  ExternalLink,
  FileText,
  Send,
  Link2,
  Copy,
  Check,
  MousePointerClick,
  CheckCircle2,
  AlertCircle
} from 'lucide-vue-next'
import {
  store,
  formatKES,
  formatHumanDate,
  formatHumanDateTime,
  fetchKcbAuditLogs,
  fetchPayments,
  fetchTenants,
  fetchLeases,
  getTenantFinancialStanding,
  fetchReminderLinks,
  runRentReminders,
  queryKcbStatus,
  resolvePendingKcbTransaction,
  type TrackedPaymentLink
} from '../data'
import { downloadReceiptPdf } from '../utils/receiptGenerator'
import { onKcbCallback, onPaymentReceived } from '../sse'
import PaginationControl from '../components/PaginationControl.vue'
import TransactionDetailsSheet from '../components/TransactionDetailsSheet.vue'
import AdminStkPushSheet from '../components/AdminStkPushSheet.vue'
import SideSheet from '../components/SideSheet.vue'
import type { Transaction, PaymentMethod, PaymentStatus, KcbTransactionRecord } from '../types'

const activeMainTab = ref<'ledger' | 'kcb_audit' | 'reminders'>('ledger')
const activeFilter = ref<'all' | PaymentMethod | PaymentStatus>('all')
const paymentSearch = ref('')
const isStkPushSheetOpen = ref(false)

// Pagination
const currentPage = ref(1)
const pageSize = ref(10)

// Transaction details side sheet
const selectedTransaction = ref<Transaction | null>(null)
const isDetailsOpen = ref(false)

function downloadTxReceipt(tx: Transaction) {
  const tenant = store.tenants.find(t => t.id === tx.tenantId) || null
  const lease = store.leases.find(l => l.id === tx.leaseId) || null
  const standing = tenant ? getTenantFinancialStanding(tenant) : null
  downloadReceiptPdf(tx, tenant, lease, standing)
}

// KCB Audit Logs
const auditLogs = ref<KcbTransactionRecord[]>([])
const isLoadingAudit = ref(false)
const auditSearch = ref('')
const selectedAuditRecord = ref<KcbTransactionRecord | null>(null)
const isAuditSheetOpen = ref(false)

// Tracked Reminder Links State
const reminderLinks = ref<TrackedPaymentLink[]>([])
const reminderStats = ref<{ total: number; active?: number; partial?: number; clicked: number; verified: number; paid: number; totalCollectedViaLinks?: number }>({
  total: 0,
  active: 0,
  partial: 0,
  clicked: 0,
  verified: 0,
  paid: 0,
  totalCollectedViaLinks: 0
})
const reminderFilter = ref<'all' | 'active' | 'history'>('all')
const isLoadingReminders = ref(false)
const isSendingReminders = ref(false)
const reminderFeedback = ref('')
const reminderError = ref('')
const copiedLinkId = ref('')

const filteredReminderLinks = computed(() => {
  if (reminderFilter.value === 'active') {
    return reminderLinks.value.filter(l => !['paid', 'expired'].includes(l.status))
  }
  if (reminderFilter.value === 'history') {
    return reminderLinks.value.filter(l => ['paid', 'expired'].includes(l.status) || (l.totalPaidViaLink || 0) > 0)
  }
  return reminderLinks.value
})

// KCB Pending Recovery & Live Sync State
const syncingRecordId = ref('')
const syncFeedback = ref('')
const syncError = ref('')
const recoveryReceipt = ref('')
const isResolvingPending = ref(false)

async function handleSyncKcbRecord(record: KcbTransactionRecord) {
  syncingRecordId.value = record.id || record.checkoutRequestId || ''
  syncFeedback.value = ''
  syncError.value = ''
  try {
    const res = await queryKcbStatus(record.checkoutRequestId, record.merchantRequestId, true)
    if (res.status === 'Success') {
      syncFeedback.value = `Confirmed! Payment of ${formatKES(Number(res.amount || record.amount))} reconciled (Ref: ${res.mpesaReceiptNumber || 'Confirmed'}).`
      await Promise.all([loadAuditLogs(), fetchPayments(), loadReminderLinks()])
      if (selectedAuditRecord.value && selectedAuditRecord.value.id === record.id) {
        selectedAuditRecord.value = auditLogs.value.find(a => a.id === record.id) || selectedAuditRecord.value
      }
    } else if (res.status === 'Failed') {
      syncFeedback.value = `Updated to Failed: ${res.resultDesc || res.statusDescription || 'Cancelled/Expired'}.`
      await loadAuditLogs()
      if (selectedAuditRecord.value && selectedAuditRecord.value.id === record.id) {
        selectedAuditRecord.value = auditLogs.value.find(a => a.id === record.id) || selectedAuditRecord.value
      }
    } else {
      syncFeedback.value = res.liveNote || 'Still pending at KCB M-Pesa. If you already received the M-Pesa SMS while the server was down, enter the receipt below to confirm.'
    }
  } catch (err: any) {
    syncError.value = err.message || 'Could not check live KCB status.'
  } finally {
    syncingRecordId.value = ''
  }
}

async function handleResolvePending(action: 'confirm' | 'fail') {
  if (!selectedAuditRecord.value) return
  syncFeedback.value = ''
  syncError.value = ''
  if (action === 'confirm' && !recoveryReceipt.value.trim()) {
    syncError.value = 'Enter the M-Pesa receipt code to confirm this payment.'
    return
  }
  isResolvingPending.value = true
  try {
    const res = await resolvePendingKcbTransaction({
      id: selectedAuditRecord.value.id,
      checkoutRequestId: selectedAuditRecord.value.checkoutRequestId,
      merchantRequestId: selectedAuditRecord.value.merchantRequestId,
      action,
      mpesaReceiptNumber: action === 'confirm' ? recoveryReceipt.value.trim().toUpperCase() : undefined
    })
    recoveryReceipt.value = ''
    syncFeedback.value = action === 'confirm'
      ? 'Payment confirmed and reconciled cleanly into the ledger!'
      : 'Marked pending STK request as Failed/Expired.'
    await Promise.all([loadAuditLogs(), fetchPayments(), loadReminderLinks()])
    if (res.record) selectedAuditRecord.value = res.record
  } catch (err: any) {
    syncError.value = err.message || 'Could not update pending transaction.'
  } finally {
    isResolvingPending.value = false
  }
}

async function loadReminderLinks() {
  isLoadingReminders.value = true
  try {
    const data = await fetchReminderLinks()
    reminderLinks.value = data.links || []
    reminderStats.value = data.stats || { total: 0, clicked: 0, verified: 0, paid: 0 }
  } catch (err) {
    console.warn('Could not load reminder links:', err)
  } finally {
    isLoadingReminders.value = false
  }
}

async function handleSendAllDueReminders() {
  isSendingReminders.value = true
  reminderFeedback.value = ''
  reminderError.value = ''
  try {
    const res = await runRentReminders({ force: true })
    reminderFeedback.value = `Reminder run finished: ${res.sent} SMS sent, ${res.skipped} skipped (settled or missing phone), ${res.failed} failed.`
    await loadReminderLinks()
  } catch (err: any) {
    reminderError.value = err.message || 'Failed to dispatch due rent reminders.'
  } finally {
    isSendingReminders.value = false
  }
}

function handleCopyPayLink(link: TrackedPaymentLink) {
  const url = link.shortUrl || `${window.location.origin}/p/${link.linkId}`
  navigator.clipboard.writeText(url)
  copiedLinkId.value = link.linkId
  setTimeout(() => {
    if (copiedLinkId.value === link.linkId) copiedLinkId.value = ''
  }, 2000)
}

async function loadAuditLogs() {
  isLoadingAudit.value = true
  try {
    auditLogs.value = await fetchKcbAuditLogs()
  } catch (err) {
    console.warn('Could not fetch audit logs:', err)
  } finally {
    isLoadingAudit.value = false
  }
}

let unsubSseCallback: (() => void) | null = null
let unsubSsePayment: (() => void) | null = null

onMounted(async () => {
  await Promise.all([fetchPayments(), fetchTenants(), fetchLeases(), loadAuditLogs(), loadReminderLinks()])

  unsubSseCallback = onKcbCallback(async () => {
    await loadAuditLogs()
    await fetchPayments()
    await loadReminderLinks()
  })

  unsubSsePayment = onPaymentReceived(async () => {
    await loadAuditLogs()
    await fetchPayments()
    await loadReminderLinks()
  })
})

onUnmounted(() => {
  if (unsubSseCallback) unsubSseCallback()
  if (unsubSsePayment) unsubSsePayment()
})

const filteredTransactions = computed(() => {
  return store.transactions.filter(t => {
    const matchesFilter =
      activeFilter.value === 'all' ||
      t.method === activeFilter.value ||
      t.status === activeFilter.value

    const q = paymentSearch.value.trim().toLowerCase()
    const matchesSearch =
      !q ||
      t.reference.toLowerCase().includes(q) ||
      t.tenantName.toLowerCase().includes(q) ||
      t.unitNumber.toLowerCase().includes(q) ||
      t.amount.toString().includes(q)

    return matchesFilter && matchesSearch
  })
})

const paginatedTransactions = computed(() => {
  const start = (currentPage.value - 1) * pageSize.value
  return filteredTransactions.value.slice(start, start + pageSize.value)
})

const filteredAuditLogs = computed(() => {
  const q = auditSearch.value.trim().toLowerCase()
  if (!q) return auditLogs.value
  return auditLogs.value.filter(
    a =>
      a.merchantRequestId?.toLowerCase().includes(q) ||
      a.checkoutRequestId?.toLowerCase().includes(q) ||
      a.phoneNumber?.includes(q) ||
      a.callerName?.toLowerCase().includes(q) ||
      a.invoiceNumber?.toLowerCase().includes(q) ||
      a.status?.toLowerCase().includes(q)
  )
})

const paginatedAuditLogs = computed(() => {
  const start = (currentPage.value - 1) * pageSize.value
  return filteredAuditLogs.value.slice(start, start + pageSize.value)
})

const auditMetrics = computed(() => {
  const total = auditLogs.value.length
  const success = auditLogs.value.filter(a => a.status === 'Success').length
  const pending = auditLogs.value.filter(a => a.status === 'Pending').length
  const failed = auditLogs.value.filter(a => a.status === 'Failed').length
  return { total, success, pending, failed }
})

function openDetails(tx: Transaction) {
  selectedTransaction.value = tx
  isDetailsOpen.value = true
}

function openAuditRecord(record: KcbTransactionRecord) {
  selectedAuditRecord.value = record
  isAuditSheetOpen.value = true
}
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">FINANCIAL REVENUE</p>
        <h1>Rent Payments</h1>
        <p>Real-time payment ledger and KCB Buni API transaction audit logs.</p>
      </div>

      <div class="intro-actions" style="display: flex; gap: 8px;">
        <button type="button" class="secondary-button" style="display: inline-flex; align-items: center; gap: 6px;"
          @click="isStkPushSheetOpen = true">
          <Smartphone :size="15" />
          <span>Initiate STK Push</span>
        </button>
        <router-link to="/payments/record" class="primary-button">
          <Plus :size="15" />
          <span>Record Payment</span>
        </router-link>
      </div>
    </header>

    <!-- Main View Switcher Tabs -->
    <div style="display: flex; gap: 10px; margin-bottom: 20px;">
      <button type="button" :class="['secondary-button', { active: activeMainTab === 'ledger' }]"
        :style="activeMainTab === 'ledger' ? 'border-color: #0f172a; background: #0f172a; color: white;' : ''"
        @click="activeMainTab = 'ledger'; currentPage = 1">
        <CreditCard :size="15" />
        <span>Rent Transactions ({{ store.transactions.length }})</span>
      </button>

      <button type="button" :class="['secondary-button', { active: activeMainTab === 'kcb_audit' }]"
        :style="activeMainTab === 'kcb_audit' ? 'border-color: #0f172a; background: #0f172a; color: white;' : ''"
        @click="activeMainTab = 'kcb_audit'; loadAuditLogs(); currentPage = 1">
        <Smartphone :size="15" />
        <span>KCB Buni STK Audit Log</span>
        <span v-if="auditLogs.length > 0" class="nav-badge" style="background: #2563eb; color: white;">{{
          auditLogs.length }}</span>
      </button>

      <button type="button" :class="['secondary-button', { active: activeMainTab === 'reminders' }]"
        :style="activeMainTab === 'reminders' ? 'border-color: #0f172a; background: #0f172a; color: white;' : ''"
        @click="activeMainTab = 'reminders'; loadReminderLinks()">
        <Link2 :size="15" />
        <span>Rent Reminders &amp; Pay Links</span>
        <span v-if="reminderLinks.length > 0" class="nav-badge" style="background: #059669; color: white;">{{
          reminderLinks.length }}</span>
      </button>
    </div>

    <!-- TAB 1: RENT TRANSACTIONS LEDGER -->
    <section v-if="activeMainTab === 'ledger'" class="structured-panel">
      <!-- Search & Filters -->
      <div class="panel-header-bar" style="flex-wrap: wrap; gap: 12px;">
        <div class="panel-filter-pills">
          <button :class="['filter-pill', { active: activeFilter === 'all' }]"
            @click="activeFilter = 'all'; currentPage = 1">
            All ({{ store.transactions.length }})
          </button>
          <button :class="['filter-pill', { active: activeFilter === 'reconciled' }]"
            @click="activeFilter = 'reconciled'; currentPage = 1">
            Reconciled
          </button>
          <button :class="['filter-pill', { active: activeFilter === 'flagged_hold' }]"
            @click="activeFilter = 'flagged_hold'; currentPage = 1">
            Unassigned (Hold)
          </button>
        </div>

        <div class="page-search-bar" style="width: 260px; margin-left: auto;">
          <Search :size="15" class="search-icon" />
          <input v-model="paymentSearch" placeholder="Search payments..." @input="currentPage = 1" />
        </div>
      </div>

      <!-- Responsive Table Wrapper -->
      <div class="table-responsive-wrapper">
        <div class="list-group-header payments-list-grid hide-mobile">
          <span>Unit Name</span>
          <span>Tenant Name</span>
          <span>Origin</span>
          <span>Date</span>
          <span>Amount</span>
          <span style="text-align: right;">Status</span>
        </div>

        <div v-for="tx in paginatedTransactions" :key="tx.id" class="list-group-row interactive-row"
          @click="openDetails(tx)">
          <!-- Desktop Row Display -->
          <div class="payments-list-grid hide-mobile">
            <div class="list-cell">
              <span class="badge occupied">Unit {{ tx.unitNumber }}</span>
            </div>

            <div class="list-cell">
              <strong style="color: #0f172a; font-size: 0.88rem;">{{ tx.tenantName }}</strong>
            </div>

            <div class="list-cell">
              <span v-if="tx.source === 'callback' || tx.reconciledBy?.includes('Webhook') || tx.method === 'stk_push'"
                class="badge"
                style="background: #ecfdf5; color: #047857; border: 1px solid #a7f3d0; font-size: 0.73rem;">
                ● M-Pesa
              </span>
              <span v-else class="badge"
                style="background: #f1f5f9; color: #475569; border: 1px solid #cbd5e1; font-size: 0.73rem;">
                ● Direct Payment
              </span>
            </div>

            <div class="list-cell">
              <span class="mono" style="font-size: 0.84rem; color: #475467;">{{ formatHumanDate(tx.date) }}</span>
            </div>

            <div class="list-cell">
              <strong style="color: #059669; font-size: 0.92rem;">{{ formatKES(tx.amount) }}</strong>
            </div>

            <div class="list-cell" style="justify-content: flex-end; gap: 8px;">
              <span :class="['badge', tx.status]">● {{ tx.status === 'reconciled' ? 'Reconciled' : 'Unassigned'
              }}</span>
              <button type="button" class="secondary-button"
                style="padding: 3px 8px; font-size: 0.74rem; height: 26px; gap: 4px;"
                title="Download Official PDF Receipt" @click.stop="downloadTxReceipt(tx)">
                <FileText :size="12" />
                <span>PDF</span>
              </button>
            </div>
          </div>

          <!-- Mobile Card Display -->
          <div class="tx-card-mobile show-mobile-only">
            <div class="tx-card-left">
              <div class="tx-card-top-row">
                <strong class="tx-card-tenant">{{ tx.tenantName }}</strong>
                <span class="badge occupied">Unit {{ tx.unitNumber }}</span>
              </div>
              <div style="display: flex; align-items: center; gap: 6px; margin-top: 3px;">
                <span
                  v-if="tx.source === 'callback' || tx.reconciledBy?.includes('Webhook') || tx.method === 'stk_push'"
                  class="badge"
                  style="background: #ecfdf5; color: #047857; border: 1px solid #a7f3d0; font-size: 0.70rem;">
                  ● M-Pesa
                </span>
                <span v-else class="badge"
                  style="background: #f1f5f9; color: #475569; border: 1px solid #cbd5e1; font-size: 0.70rem;">
                  ● Direct Payment
                </span>
                <span class="tx-card-time">{{ formatHumanDateTime(tx.timestamp || tx.date) }}</span>
              </div>
            </div>

            <div class="tx-card-right">
              <strong class="tx-card-amount">{{ formatKES(tx.amount) }}</strong>
              <span :class="['badge', tx.status]">● {{ tx.status === 'reconciled' ? 'Reconciled' : 'Unassigned'
              }}</span>
            </div>
          </div>
        </div>
      </div>

      <div v-if="paginatedTransactions.length === 0" style="padding: 36px; text-align: center; color: #64748b;">
        No payment records found matching your query.
      </div>

      <PaginationControl v-model:current-page="currentPage" v-model:page-size="pageSize"
        :total-items="filteredTransactions.length" />
    </section>

    <!-- TAB 2: KCB BUNI API AUDIT LOG -->
    <section v-if="activeMainTab === 'kcb_audit'" class="structured-panel">
      <!-- Audit Metric Summary -->
      <div
        style="display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; padding: 18px; background: #f8fafc; border-bottom: 1px solid #eef2f6;">
        <div>
          <span style="font-size: 0.76rem; text-transform: uppercase; color: #64748b; font-weight: 600;">Total API
            Calls</span>
          <div style="font-size: 1.3rem; font-weight: 700; color: #0f172a;">{{ auditMetrics.total }}</div>
        </div>
        <div>
          <span style="font-size: 0.76rem; text-transform: uppercase; color: #059669; font-weight: 600;">Successful
            Payments</span>
          <div style="font-size: 1.3rem; font-weight: 700; color: #059669;">{{ auditMetrics.success }}</div>
        </div>
        <div>
          <span style="font-size: 0.76rem; text-transform: uppercase; color: #2563eb; font-weight: 600;">Pending
            Confirmation</span>
          <div style="font-size: 1.3rem; font-weight: 700; color: #2563eb;">{{ auditMetrics.pending }}</div>
        </div>
        <div>
          <span style="font-size: 0.76rem; text-transform: uppercase; color: #dc2626; font-weight: 600;">Failed /
            Cancelled</span>
          <div style="font-size: 1.3rem; font-weight: 700; color: #dc2626;">{{ auditMetrics.failed }}</div>
        </div>
      </div>

      <!-- Header with Refresh & Search -->
      <div class="panel-header-bar" style="flex-wrap: wrap; gap: 12px;">
        <div style="display: flex; align-items: center; gap: 8px;">
          <button type="button" class="secondary-button" style="padding: 6px 12px;" @click="loadAuditLogs">
            <RefreshCw :size="14" :class="{ 'animate-spin': isLoadingAudit }" />
            <span>Refresh</span>
          </button>
          <span style="font-size: 0.80rem; color: #64748b;">KCB Buni UAT Gateway Logs</span>
        </div>

        <div class="page-search-bar" style="width: 260px; margin-left: auto;">
          <Search :size="15" class="search-icon" />
          <input v-model="auditSearch" placeholder="Filter by invoice, phone, status..." @input="currentPage = 1" />
        </div>
      </div>

      <!-- Audit Table -->
      <div class="table-responsive-wrapper">
        <div class="list-group-header hide-mobile"
          style="display: grid; grid-template-columns: 140px 150px 120px 100px 140px 100px 70px; gap: 12px; padding: 12px 18px; font-size: 0.78rem; font-weight: 600; color: #64748b; border-bottom: 1px solid #eef2f6;">
          <span>Timestamp</span>
          <span>Initiator / Caller</span>
          <span>Phone</span>
          <span>Amount</span>
          <span>Invoice / Ref</span>
          <span>Status</span>
          <span style="text-align: right;">View</span>
        </div>

        <div v-for="a in paginatedAuditLogs" :key="a.id" class="list-group-row interactive-row"
          style="cursor: pointer; padding: 12px 18px;" @click="openAuditRecord(a)">
          <div class="hide-mobile"
            style="display: grid; grid-template-columns: 140px 150px 120px 100px 140px 100px 70px; gap: 12px; align-items: center; width: 100%;">
            <div>
              <span class="mono" style="font-size: 0.80rem; color: #475467;">{{ formatHumanDate(a.createdAt) }}</span>
            </div>
            <div>
              <strong style="font-size: 0.85rem; color: #0f172a; display: block;">{{ a.callerName || 'Resident'
              }}</strong>
              <small style="font-size: 0.74rem; color: #64748b;">{{ a.callerRole || 'web' }}</small>
            </div>
            <div>
              <span class="mono" style="font-size: 0.82rem; color: #334155;">{{ a.phoneNumber }}</span>
            </div>
            <div>
              <strong style="color: #059669; font-size: 0.88rem;">{{ formatKES(a.amount) }}</strong>
            </div>
            <div>
              <span class="mono" style="font-size: 0.78rem; color: #475467;">{{ a.invoiceNumber }}</span>
            </div>
            <div>
              <span :class="['badge', a.status === 'Success' ? 'paid' : a.status === 'Pending' ? 'active' : 'overdue']"
                style="font-size: 0.74rem;">
                ● {{ a.status }}
              </span>
            </div>
            <div style="text-align: right;">
              <button type="button" class="secondary-button" style="padding: 3px 8px; font-size: 0.74rem;">
                JSON
              </button>
            </div>
          </div>

          <!-- Mobile display -->
          <div class="show-mobile-only" style="width: 100%;">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
              <strong style="font-size: 0.88rem; color: #0f172a;">{{ a.callerName || 'Resident' }} · {{ a.phoneNumber
              }}</strong>
              <strong style="color: #059669; font-size: 0.90rem;">{{ formatKES(a.amount) }}</strong>
            </div>
            <div
              style="display: flex; justify-content: space-between; align-items: center; font-size: 0.76rem; color: #64748b;">
              <span class="mono">{{ a.invoiceNumber }} · {{ formatHumanDate(a.createdAt) }}</span>
              <span :class="['badge', a.status === 'Success' ? 'paid' : a.status === 'Pending' ? 'active' : 'overdue']">
                {{ a.status }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <div v-if="filteredAuditLogs.length === 0" style="padding: 36px; text-align: center; color: #64748b;">
        No KCB transaction audit records found.
      </div>

      <PaginationControl v-model:current-page="currentPage" v-model:page-size="pageSize"
        :total-items="filteredAuditLogs.length" />
    </section>

    <!-- TAB 3: RENT REMINDERS & TRACKED PAYMENT LINKS -->
    <section v-if="activeMainTab === 'reminders'" class="structured-panel">
      <div class="panel-header-bar" style="flex-wrap: wrap; gap: 12px; justify-content: space-between;">
        <div>
          <h3 style="font-size: 1rem; margin: 0 0 2px;">Tracked Rent Reminder Links</h3>
          <p style="font-size: 0.8rem; color: #64748b; margin: 0;">
            <!-- Each rent reminder SMS sends a unique payment link (<span class="mono">/p/&lt;id&gt;</span>) that tracks -->
            Each rent reminder SMS sends a unique payment link that tracks
            link clicks, phone OTP verification, and M-Pesa payment conversion.
          </p>
        </div>

        <div style="display: flex; gap: 8px; align-items: center;">
          <button type="button" class="secondary-button" :disabled="isLoadingReminders" @click="loadReminderLinks">
            <RefreshCw :size="14" :class="{ 'animate-spin': isLoadingReminders }" />
            <span>Refresh</span>
          </button>
          <button type="button" class="primary-button" :disabled="isSendingReminders"
            @click="handleSendAllDueReminders">
            <Send :size="14" />
            <span>{{ isSendingReminders ? 'Sending Reminders...' : 'Send Due Rent Reminders' }}</span>
          </button>
        </div>
      </div>

      <div v-if="reminderFeedback"
        style="margin: 12px 18px 0; padding: 10px 14px; background: #ecfdf5; border: 1px solid #a7f3d0; color: #047857; border-radius: 6px; font-size: 0.84rem; display: flex; align-items: center; gap: 8px;">
        <CheckCircle2 :size="15" />
        <span>{{ reminderFeedback }}</span>
      </div>

      <div v-if="reminderError"
        style="margin: 12px 18px 0; padding: 10px 14px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.84rem; display: flex; align-items: center; gap: 8px;">
        <AlertCircle :size="15" />
        <span>{{ reminderError }}</span>
      </div>

      <!-- Funnel KPI Row -->
      <div
        style="display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; padding: 16px 18px; border-bottom: 1px solid #eef2f6;">
        <div style="padding: 12px 14px; border: 1px solid #e2e8f0; border-radius: 8px; background: #fafbfc;">
          <div style="font-size: 0.74rem; color: #64748b; font-weight: 600;">Active Links</div>
          <div style="font-size: 1.35rem; font-weight: 800; color: #172033; margin-top: 4px;">{{ reminderStats.active ??
            reminderStats.total }}</div>
        </div>
        <div style="padding: 12px 14px; border: 1px solid #e2e8f0; border-radius: 8px; background: #fafbfc;">
          <div style="font-size: 0.74rem; color: #64748b; font-weight: 600;">Clicked Link</div>
          <div style="font-size: 1.35rem; font-weight: 800; color: #2563eb; margin-top: 4px;">{{ reminderStats.clicked
          }}</div>
        </div>
        <div style="padding: 12px 14px; border: 1px solid #e2e8f0; border-radius: 8px; background: #fafbfc;">
          <div style="font-size: 0.74rem; color: #64748b; font-weight: 600;">Settled / Done</div>
          <div style="font-size: 1.35rem; font-weight: 800; color: #059669; margin-top: 4px;">{{ reminderStats.paid }}
          </div>
        </div>
        <div style="padding: 12px 14px; border: 1px solid #e2e8f0; border-radius: 8px; background: #ecfdf5;">
          <div style="font-size: 0.74rem; color: #047857; font-weight: 600;">Collected via Links</div>
          <div style="font-size: 1.35rem; font-weight: 800; color: #059669; margin-top: 4px;">{{
            formatKES(reminderStats.totalCollectedViaLinks || 0) }}</div>
        </div>
      </div>

      <!-- Filter Pills: All / Active / Pay Links History -->
      <div style="display: flex; gap: 8px; padding: 12px 18px; border-bottom: 1px solid #f1f5f9;">
        <button type="button" :class="['filter-pill', { active: reminderFilter === 'all' }]"
          @click="reminderFilter = 'all'">
          All Links ({{ reminderLinks.length }})
        </button>
        <button type="button" :class="['filter-pill', { active: reminderFilter === 'active' }]"
          @click="reminderFilter = 'active'">
          Active Unsettled ({{reminderLinks.filter(l => !['paid', 'expired'].includes(l.status)).length}})
        </button>
        <button type="button" :class="['filter-pill', { active: reminderFilter === 'history' }]"
          @click="reminderFilter = 'history'">
          Pay Links History ({{reminderLinks.filter(l => ['paid', 'expired'].includes(l.status) || (l.totalPaidViaLink
            || 0) > 0).length}})
        </button>
      </div>

      <!-- Tracked Links Table -->
      <div style="overflow-x: auto;">
        <table v-if="filteredReminderLinks.length > 0"
          style="width: 100%; border-collapse: collapse; font-size: 0.83rem;">
          <thead>
            <tr
              style="border-bottom: 1px solid #e2e8f0; background: #f8fafc; color: #64748b; text-align: left; font-size: 0.74rem; text-transform: uppercase; letter-spacing: 0.04em;">
              <th style="padding: 10px 14px;">Resident &amp; Unit</th>
              <th style="padding: 10px 12px;">Link ID &amp; Cycle</th>
              <th style="padding: 10px 12px;">Paid So Far / Remaining</th>
              <th style="padding: 10px 12px;">SMS Delivery</th>
              <th style="padding: 10px 12px;">Link Clicks</th>
              <th style="padding: 10px 12px;">Status</th>
              <th style="padding: 10px 14px; text-align: right;">Action</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="link in filteredReminderLinks" :key="link.linkId" style="border-bottom: 1px solid #f1f5f9;">
              <td style="padding: 12px 14px;">
                <div style="font-weight: 700; color: #172033;">{{ link.tenantName }}</div>
                <div style="font-size: 0.76rem; color: #64748b;">
                  Unit {{ link.unitNumber }} · {{ link.remindersSentCount || 1 }} reminder{{ (link.remindersSentCount ||
                    1) === 1 ? '' : 's' }}
                </div>
              </td>
              <td style="padding: 12px 12px;">
                <span class="mono" style="font-weight: 600; font-size: 0.78rem; color: #2563eb;">{{ link.linkId
                }}</span>
                <div style="font-size: 0.72rem; color: #64748b;">
                  {{ link.billingMonths && link.billingMonths.length > 1 ? link.billingMonths.join(', ') :
                    link.billingMonth }}
                </div>
              </td>
              <td style="padding: 12px 12px;">
                <div style="font-weight: 700; color: #059669;">
                  Paid: {{ formatKES(link.totalPaidViaLink ?? link.paidAmount ?? 0) }}
                </div>
                <div style="font-size: 0.75rem; color: #64748b;">
                  Remaining: <strong
                    :style="{ color: (link.remainingBalance ?? link.amountDueAtSend) > 0 ? '#b91c1c' : '#059669' }">{{
                      formatKES(link.remainingBalance ?? link.amountDueAtSend) }}</strong>
                </div>
              </td>
              <td style="padding: 12px 12px;">
                <span
                  :class="['badge', link.smsDeliveryStatus === 'Delivered' ? 'paid' : link.smsDeliveryStatus === 'Accepted' ? 'active' : 'overdue']"
                  style="font-size: 0.72rem;">
                  {{ link.smsDeliveryStatus || 'Accepted' }}
                </span>
              </td>
              <td style="padding: 12px 12px;">
                <div style="display: inline-flex; align-items: center; gap: 5px; font-weight: 600; color: #172033;">
                  <MousePointerClick :size="13" style="color: #2563eb;" />
                  <span>{{ link.clickCount || 0 }} click{{ (link.clickCount || 0) === 1 ? '' : 's' }}</span>
                </div>
                <div v-if="link.lastClickedAt" style="font-size: 0.72rem; color: #64748b;">
                  Last: {{ formatHumanDateTime(link.lastClickedAt) }}
                </div>
                <div v-else style="font-size: 0.72rem; color: #94a3b8;">Not opened yet</div>
              </td>
              <td style="padding: 12px 12px;">
                <span
                  :class="['badge', link.status === 'paid' ? 'paid' : (link.status === 'partial' || link.status === 'verified' || link.status === 'clicked') ? 'active' : 'pending']"
                  style="font-size: 0.72rem; text-transform: capitalize;">
                  {{ link.status === 'paid' ? 'Completed' : link.status === 'partial' ? 'Partial Paid' : link.status ===
                    'verified' ? 'OTP Verified' : link.status === 'clicked' ? 'Clicked' : 'Sent' }}
                </span>
                <div v-if="link.mpesaReceipt" class="mono" style="font-size: 0.72rem; color: #059669; margin-top: 3px;">
                  {{ link.mpesaReceipt }}
                </div>
              </td>
              <td style="padding: 12px 14px; text-align: right;">
                <button type="button" class="secondary-button" style="font-size: 0.76rem; padding: 5px 10px;"
                  @click="handleCopyPayLink(link)">
                  <Check v-if="copiedLinkId === link.linkId" :size="13" />
                  <Copy v-else :size="13" />
                  <span>{{ copiedLinkId === link.linkId ? 'Copied' : 'Copy Link' }}</span>
                </button>
              </td>
            </tr>
          </tbody>
        </table>

        <div v-else style="padding: 40px; text-align: center; color: #64748b;">
          No payment links in this view yet. Click <strong>Send Due Rent Reminders</strong> above to dispatch reminders.
        </div>
      </div>
    </section>

    <!-- Concise Transaction Details Side Sheet -->
    <TransactionDetailsSheet :open="isDetailsOpen" :transaction="selectedTransaction" @close="isDetailsOpen = false" />

    <!-- KCB Audit Details Side Sheet (Includes Live Sync & Missed Callback Recovery for Pending STK) -->
    <SideSheet :open="isAuditSheetOpen" title="KCB API Transaction Audit"
      :subtitle="`Merchant Req #${selectedAuditRecord?.merchantRequestId || selectedAuditRecord?.checkoutRequestId || ''}`"
      @close="isAuditSheetOpen = false; syncFeedback = ''; syncError = ''; recoveryReceipt = ''">
      <div v-if="selectedAuditRecord" style="display: flex; flex-direction: column; gap: 18px;">
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <span
            :class="['badge', selectedAuditRecord.status === 'Success' ? 'paid' : selectedAuditRecord.status === 'Pending' ? 'active' : 'overdue']">
            ● {{ selectedAuditRecord.status.toUpperCase() }}
          </span>
          <strong style="font-size: 1.1rem; color: #059669;">{{ formatKES(selectedAuditRecord.amount) }}</strong>
        </div>

        <div v-if="syncFeedback" class="auth-alert success" style="margin: 0;">
          <CheckCircle2 :size="15" class="auth-alert-icon" />
          <span>{{ syncFeedback }}</span>
        </div>
        <div v-if="syncError" class="auth-alert error" style="margin: 0;">
          <AlertCircle :size="15" class="auth-alert-icon" />
          <span>{{ syncError }}</span>
        </div>

        <!-- Pending STK Status Sync & Missed Callback Recovery -->
        <div v-if="selectedAuditRecord.status === 'Pending'"
          style="padding: 14px; border: 1px solid #bfdbfe; background: #eff6ff; border-radius: 8px; display: flex; flex-direction: column; gap: 12px;">
          <div style="display: flex; align-items: center; justify-content: space-between; gap: 10px; flex-wrap: wrap;">
            <div>
              <strong style="font-size: 0.86rem; color: #1e3a8a; display: block;">Pending STK Push — Sync
                Status</strong>
              <small style="font-size: 0.76rem; color: #475569;">Query KCB live if a callback was missed while the
                server was down.</small>
            </div>
            <button type="button" class="primary-button" style="padding: 6px 12px; font-size: 0.78rem;"
              :disabled="syncingRecordId === (selectedAuditRecord.id || selectedAuditRecord.checkoutRequestId)"
              @click="handleSyncKcbRecord(selectedAuditRecord)">
              <RefreshCw :size="13"
                :class="{ 'animate-spin': syncingRecordId === (selectedAuditRecord.id || selectedAuditRecord.checkoutRequestId) }" />
              <span>{{ syncingRecordId ? 'Checking KCB...' : 'Check Status Now' }}</span>
            </button>
          </div>

          <div style="border-top: 1px solid #dbeafe; padding-top: 10px;">
            <small style="font-size: 0.75rem; color: #334155; font-weight: 600; display: block; margin-bottom: 6px;">
              Manual Recovery (if payment completed during server downtime)
            </small>
            <div style="display: flex; gap: 8px; flex-wrap: wrap;">
              <input v-model="recoveryReceipt" placeholder="M-Pesa Receipt (e.g. UKQ3N3Y4JX)" class="mono"
                style="flex: 1; min-width: 160px; padding: 7px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 0.8rem; background: #fff;" />
              <button type="button" class="secondary-button"
                style="font-size: 0.78rem; padding: 6px 10px; color: #059669; border-color: #a7f3d0;"
                :disabled="isResolvingPending" @click="handleResolvePending('confirm')">
                Confirm Paid
              </button>
              <button type="button" class="secondary-button"
                style="font-size: 0.78rem; padding: 6px 10px; color: #b91c1c; border-color: #fecaca;"
                :disabled="isResolvingPending" @click="handleResolvePending('fail')">
                Mark Failed
              </button>
            </div>
          </div>
        </div>

        <div class="spec-grid" style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
          <div class="spec-item">
            <span class="spec-label">Initiator / Caller</span>
            <strong class="spec-value">{{ selectedAuditRecord.callerName }}</strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Caller Role</span>
            <strong class="spec-value">{{ selectedAuditRecord.callerRole }}</strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Phone Number</span>
            <strong class="spec-value mono">{{ selectedAuditRecord.phoneNumber }}</strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Invoice Ref</span>
            <strong class="spec-value mono">{{ selectedAuditRecord.invoiceNumber }}</strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Checkout Request ID</span>
            <strong class="spec-value mono" style="font-size: 0.74rem;">{{ selectedAuditRecord.checkoutRequestId ||
              'N/A' }}</strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Caller IP</span>
            <strong class="spec-value mono">{{ selectedAuditRecord.callerIp || '127.0.0.1' }}</strong>
          </div>
          <div v-if="selectedAuditRecord.mpesaReceiptNumber" class="spec-item" style="grid-column: span 2;">
            <span class="spec-label">Confirmed M-Pesa Receipt</span>
            <strong class="spec-value mono" style="color: #059669;">{{ selectedAuditRecord.mpesaReceiptNumber
            }}</strong>
          </div>
          <div v-if="selectedAuditRecord.statusDescription" class="spec-item" style="grid-column: span 2;">
            <span class="spec-label">Status Description</span>
            <p style="font-size: 0.82rem; color: #475467; margin-top: 4px;">{{ selectedAuditRecord.statusDescription }}
            </p>
          </div>
        </div>

        <!-- Raw JSON Payload View -->
        <div style="margin-top: 10px;">
          <span class="spec-label" style="display: block; margin-bottom: 6px;">Raw Gateway Payload</span>
          <pre
            style="padding: 12px; background: #0f172a; color: #38bdf8; border-radius: 6px; font-size: 0.74rem; overflow-x: auto; max-height: 200px;">{{ JSON.stringify(selectedAuditRecord.rawResponse || selectedAuditRecord.rawCallback || selectedAuditRecord, null, 2) }}</pre>
        </div>
      </div>
    </SideSheet>

    <!-- Admin STK Push SideSheet -->
    <AdminStkPushSheet :open="isStkPushSheetOpen" @close="isStkPushSheetOpen = false"
      @success="() => { fetchPayments(); loadAuditLogs() }" />
  </div>
</template>

<style scoped>
.payments-list-grid {
  display: grid;
  grid-template-columns: 120px 1.4fr 140px 110px 120px 120px;
  gap: 12px;
}

.payments-mobile-grid {
  display: grid;
  grid-template-columns: 1.3fr 1.1fr 1fr;
  gap: 8px;
}

.interactive-row {
  cursor: pointer;
  transition: background 0.12s ease;
}

.interactive-row:hover {
  background: #f8fafc;
}
</style>
