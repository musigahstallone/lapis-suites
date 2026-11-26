<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import {
  ShieldCheck,
  CheckCircle2,
  AlertTriangle,
  Search,
  Plus,
  ArrowRight,
  ExternalLink,
  Phone,
  FileCode,
  Smartphone,
  Check,
  X
} from 'lucide-vue-next'
import {
  store,
  formatKES,
  formatHumanDate,
  formatHumanDateTime,
  reconcilePayment,
  fetchPayments
} from '../data'
import { onKcbCallback } from '../sse'
import PaginationControl from '../components/PaginationControl.vue'
import TransactionDetailsSheet from '../components/TransactionDetailsSheet.vue'
import SideSheet from '../components/SideSheet.vue'
import SearchableSelect from '../components/SearchableSelect.vue'
import type { Transaction, DarajaCallbackPayload } from '../types'

// Active View Tab: 'ledger' vs 'callbacks'
const activeTab = ref<'ledger' | 'callbacks'>('ledger')

// Callbacks State
const callbacks = ref<any[]>([])
const selectedCallback = ref<any | null>(null)
const isCallbackDetailsOpen = ref(false)

async function fetchCallbacks() {
  try {
    const headers: Record<string, string> = {}
    if (store.session.token) headers['Authorization'] = `Bearer ${store.session.token}`
    const res = await fetch('/api/kcb/callbacks', { headers })
    if (res.ok) {
      callbacks.value = await res.json()
    }
  } catch (err) {
    console.warn('Could not fetch callbacks:', err)
  }
}

let unsubSseCallback: (() => void) | null = null

onMounted(async () => {
  await Promise.all([fetchPayments(), fetchCallbacks()])

  // Real-time listener for incoming M-Pesa IPN callbacks
  unsubSseCallback = onKcbCallback((data) => {
    if (data.callback) {
      callbacks.value.unshift(data.callback)
    }
    fetchPayments()
  })
})

onUnmounted(() => {
  if (unsubSseCallback) unsubSseCallback()
})

// Pagination for reconciled table
const currentPage = ref(1)
const pageSize = ref(10)

// Side Sheet for details
const selectedTransaction = ref<Transaction | null>(null)
const isDetailsOpen = ref(false)

// Manual Reconciliation Modal
const isReconcileModalOpen = ref(false)
const txToReconcile = ref<Transaction | null>(null)
const selectedTenantId = ref('')
const selectedUnitId = ref('')
const reconcileNote = ref('')
const reconcileError = ref('')

// Summary Metrics
const totalCount = computed(() => store.transactions.length)
const totalAmount = computed(() => store.transactions.reduce((sum, t) => sum + t.amount, 0))

const reconciledTransactions = computed(() => {
  return store.transactions.filter(t => t.reconciled && t.status === 'reconciled')
})
const reconciledCount = computed(() => reconciledTransactions.value.length)
const reconciledAmount = computed(() => reconciledTransactions.value.reduce((sum, t) => sum + t.amount, 0))

const unassignedTransactions = computed(() => {
  return store.transactions.filter(t => !t.reconciled || t.status === 'flagged_hold')
})
const unassignedCount = computed(() => unassignedTransactions.value.length)
const unassignedAmount = computed(() => unassignedTransactions.value.reduce((sum, t) => sum + t.amount, 0))

const paginatedReconciled = computed(() => {
  const start = (currentPage.value - 1) * pageSize.value
  return reconciledTransactions.value.slice(start, start + pageSize.value)
})

// Searchable Select Options
const tenantOptions = computed(() => {
  return store.tenants.map(t => ({
    value: t.id,
    label: t.name,
    sublabel: `${t.phone} · Unit ${t.currentUnitNumber || 'Unassigned'}`
  }))
})

const unitOptions = computed(() => {
  return store.units.map(u => ({
    value: u.id,
    label: `Unit ${u.unitNumber} (${u.type})`,
    sublabel: u.status === 'occupied' ? 'Occupied' : 'Vacant'
  }))
})

function openManualReconciliation(tx: Transaction) {
  txToReconcile.value = tx
  selectedTenantId.value = tx.tenantId || ''
  selectedUnitId.value = tx.unitId || ''
  reconcileNote.value = `Manual reconciliation for ${tx.reference}. Verified funds received.`
  reconcileError.value = ''
  isReconcileModalOpen.value = true
}

function handleTenantChange(tenantId: string) {
  const tenant = store.tenants.find(t => t.id === tenantId)
  if (tenant && tenant.currentUnitId) {
    selectedUnitId.value = tenant.currentUnitId
  }
}

async function handleExecuteReconcile() {
  if (!txToReconcile.value) return
  if (!selectedTenantId.value) {
    reconcileError.value = 'Please select a resident to map this payment to.'
    return
  }
  if (!selectedUnitId.value) {
    reconcileError.value = 'Please select a unit to map this payment to.'
    return
  }

  try {
    await reconcilePayment(
      txToReconcile.value.id,
      selectedTenantId.value,
      selectedUnitId.value,
      reconcileNote.value
    )
    isReconcileModalOpen.value = false
    txToReconcile.value = null
  } catch (err: any) {
    reconcileError.value = err.message || 'Failed to reconcile payment.'
  }
}

function openDetails(tx: Transaction) {
  selectedTransaction.value = tx
  isDetailsOpen.value = true
}

function openCallbackDetails(cb: any) {
  selectedCallback.value = cb
  isCallbackDetailsOpen.value = true
}
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">DARAJA WEBHOOK & RECONCILIATION</p>
        <h1>Payments & Reconciliation</h1>
        <p>Automated M-Pesa C2B matching engine with manual assignment workflow for unmapped remittances.</p>
      </div>
    </header>

    <!-- Summary Metrics: Total vs Reconciled vs Unassigned -->
    <section class="stats-grid" style="margin-bottom: 24px;">
      <article class="stat-card">
        <div class="stat-label">Total Transactions</div>
        <div class="stat-value">{{ totalCount }}</div>
        <div class="stat-trend neutral">
          <span>{{ formatKES(totalAmount) }} cumulative volume</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Reconciled Payments</div>
        <div class="stat-value text-positive">{{ reconciledCount }}</div>
        <div class="stat-trend positive">
          <span>{{ formatKES(reconciledAmount) }} reconciled</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Unassigned Payments</div>
        <div class="stat-value text-danger">{{ unassignedCount }}</div>
        <div class="stat-trend negative">
          <span>{{ formatKES(unassignedAmount) }} pending assignment</span>
        </div>
      </article>
    </section>

    <!-- Unassigned Payments Queue (Awaiting Manual Reconciliation) -->
    <section v-if="unassignedTransactions.length > 0" class="structured-panel" style="border-color: #fde68a;">
      <div class="panel-header-bar" style="background: #fffbeb;">
        <div class="panel-header-title">
          <h2 style="color: #92400e;">Unassigned Payments Queue ({{ unassignedCount }})</h2>
          <p style="color: #b45309;">
            Remittances received via Daraja webhook requiring manual mapping to a resident and unit.
          </p>
        </div>
      </div>

      <div style="padding: 16px; display: flex; flex-direction: column; gap: 12px;">
        <div
          v-for="tx in unassignedTransactions"
          :key="tx.id"
          class="unassigned-item"
        >
          <div class="unassigned-details">
            <div style="display: flex; align-items: center; gap: 8px;">
              <strong class="mono" style="font-size: 0.95rem; color: #1e3a8a;">{{ tx.reference }}</strong>
              <span class="badge overdue">● Unassigned</span>
              <span class="mono" style="font-size: 0.8rem; color: #64748b;">{{ tx.date }}</span>
            </div>

            <p style="font-size: 0.84rem; color: #334155; margin: 4px 0 0;">
              Remitter: <strong>{{ tx.payerName || tx.tenantName }}</strong> · Phone: <span class="mono">{{ tx.phoneNumber }}</span> · Account: <span class="mono">{{ tx.billRefNumber }}</span>
            </p>
          </div>

          <div class="unassigned-actions">
            <strong style="color: #059669; font-size: 1.05rem;">{{ formatKES(tx.amount) }}</strong>
            <button
              type="button"
              class="primary-button"
              style="padding: 6px 14px; font-size: 0.82rem;"
              @click="openManualReconciliation(tx)"
            >
              <span>Reconcile Payment</span>
            </button>
            <button
              type="button"
              class="secondary-button"
              style="padding: 6px 10px; font-size: 0.82rem;"
              @click="openDetails(tx)"
            >
              <span>Payload</span>
            </button>
          </div>
        </div>
      </div>
    </section>

    <!-- View Selector Tabs: Ledger vs M-Pesa IPN Callbacks -->
    <div style="display: flex; gap: 8px; margin-top: 24px; margin-bottom: 14px;">
      <button
        type="button"
        :class="['secondary-button', { active: activeTab === 'ledger' }]"
        :style="activeTab === 'ledger' ? 'background: #0f172a; color: white; border-color: #0f172a;' : ''"
        style="padding: 8px 16px; font-weight: 600; display: inline-flex; align-items: center; gap: 6px;"
        @click="activeTab = 'ledger'"
      >
        <ShieldCheck :size="15" />
        <span>Reconciled Ledger ({{ reconciledCount }})</span>
      </button>
      <button
        type="button"
        :class="['secondary-button', { active: activeTab === 'callbacks' }]"
        :style="activeTab === 'callbacks' ? 'background: #0f172a; color: white; border-color: #0f172a;' : ''"
        style="padding: 8px 16px; font-weight: 600; display: inline-flex; align-items: center; gap: 6px;"
        @click="activeTab = 'callbacks'"
      >
        <Smartphone :size="15" />
        <span>M-Pesa IPN Callbacks ({{ callbacks.length }})</span>
      </button>
    </div>

    <!-- Reconciled Ledger Table -->
    <section v-if="activeTab === 'ledger'" class="structured-panel">
      <div class="panel-header-bar">
        <div class="panel-header-title">
          <h2>Reconciled Ledger Transactions ({{ reconciledCount }})</h2>
          <p>Verified funds matched to residents and processed through the automated lease billing engine.</p>
        </div>
      </div>

      <!-- Responsive Table Wrapper for Tablet & Small Laptop (Zero Aggressive Compression) -->
      <div class="table-responsive-wrapper">
        <!-- Desktop List Header: Unit Name, Tenant Name, Date, Amount, Status (Single header, hidden <= 768px) -->
        <div class="list-group-header payments-list-grid hide-mobile">
          <span>Unit</span>
          <span>Resident</span>
          <span>Date</span>
          <span>Amount</span>
          <span style="text-align: right;">Status</span>
        </div>

        <!-- Rows -->
        <div
          v-for="tx in paginatedReconciled"
          :key="tx.id"
          class="list-group-row interactive-row"
          @click="openDetails(tx)"
        >
          <!-- Desktop Row (Single Horizontal Line with Ellipsis Protection) -->
          <div class="payments-list-grid hide-mobile">
            <div class="list-cell">
              <span class="badge occupied">Unit {{ tx.unitNumber }}</span>
            </div>

            <div class="list-cell">
              <strong style="color: #0f172a; font-size: 0.88rem;">{{ tx.tenantName }}</strong>
            </div>

            <div class="list-cell">
              <span class="mono" style="font-size: 0.84rem; color: #475467;">{{ formatHumanDate(tx.date) }}</span>
            </div>

            <div class="list-cell">
              <strong style="color: #059669; font-size: 0.92rem;">{{ formatKES(tx.amount) }}</strong>
            </div>

            <div class="list-cell" style="justify-content: flex-end;">
              <span class="badge paid">● Reconciled</span>
            </div>
          </div>

          <!-- Mobile Card Display: Tenant Name top-left, Unit badge beside, humanized date bottom-left; Bold KES top-right, status beneath -->
          <div class="tx-card-mobile show-mobile-only">
            <div class="tx-card-left">
              <div class="tx-card-top-row">
                <strong class="tx-card-tenant">{{ tx.tenantName }}</strong>
                <span class="badge occupied">Unit {{ tx.unitNumber }}</span>
              </div>
              <span class="tx-card-time">{{ formatHumanDateTime(tx.timestamp || tx.date) }}</span>
            </div>

            <div class="tx-card-right">
              <strong class="tx-card-amount">{{ formatKES(tx.amount) }}</strong>
              <span class="badge paid">● Reconciled</span>
            </div>
          </div>
        </div>
      </div>

      <div v-if="paginatedReconciled.length === 0" style="padding: 36px; text-align: center; color: #64748b;">
        No reconciled payments recorded.
      </div>

      <PaginationControl
        v-model:current-page="currentPage"
        v-model:page-size="pageSize"
        :total-items="reconciledTransactions.length"
      />
    </section>

    <!-- M-Pesa IPN Webhook Callbacks Table -->
    <section v-if="activeTab === 'callbacks'" class="structured-panel">
      <div class="panel-header-bar">
        <div class="panel-header-title">
          <h2>Parsed M-Pesa IPN Callbacks ({{ callbacks.length }})</h2>
          <p>Real-time stream of incoming M-Pesa & KCB Buni webhook notifications, with automatic data extraction and ledger mapping.</p>
        </div>
      </div>

      <div class="table-responsive-wrapper">
        <div class="list-group-header hide-mobile" style="display: grid; grid-template-columns: 140px 130px 120px 100px 140px 1.2fr 80px; gap: 12px; padding: 12px 18px; font-size: 0.78rem; font-weight: 600; color: #64748b; border-bottom: 1px solid #eef2f6;">
          <span>Received At</span>
          <span>Receipt No</span>
          <span>Phone</span>
          <span>Amount</span>
          <span>Status</span>
          <span>Matched Agreement</span>
          <span style="text-align: right;">Payload</span>
        </div>

        <div
          v-for="cb in callbacks"
          :key="cb.id"
          class="list-group-row interactive-row"
          style="cursor: pointer; padding: 12px 18px;"
          @click="openCallbackDetails(cb)"
        >
          <div class="hide-mobile" style="display: grid; grid-template-columns: 140px 130px 120px 100px 140px 1.2fr 80px; gap: 12px; align-items: center; width: 100%;">
            <span class="mono" style="font-size: 0.80rem; color: #475467;">
              {{ formatHumanDateTime(cb.receivedAt || cb.parsed?.transactionDate) }}
            </span>
            <strong class="mono" style="font-size: 0.88rem; color: #1e3a8a;">
              {{ cb.parsed?.mpesaReceiptNumber || 'N/A' }}
            </strong>
            <span class="mono" style="font-size: 0.82rem; color: #334155;">
              {{ cb.parsed?.phoneNumber || 'N/A' }}
            </span>
            <strong style="color: #059669; font-size: 0.90rem;">
              {{ formatKES(cb.parsed?.amount || 0) }}
            </strong>
            <div>
              <span v-if="cb.parsed?.isSuccess" class="badge" style="background: #ecfdf5; color: #047857; border: 1px solid #a7f3d0; font-size: 0.74rem;">
                ● Success
              </span>
              <span v-else class="badge overdue" style="font-size: 0.74rem;">
                ● {{ cb.parsed?.resultDesc || 'Failed' }}
              </span>
            </div>
            <div style="font-size: 0.82rem; color: #334155; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">
              <strong>{{ cb.parsed?.matchedTenantName || 'Resident' }}</strong>
              <span v-if="cb.parsed?.matchedUnitNumber"> (Unit {{ cb.parsed?.matchedUnitNumber }})</span>
            </div>
            <div style="text-align: right;">
              <button
                type="button"
                class="secondary-button"
                style="padding: 4px 10px; font-size: 0.75rem;"
                @click.stop="openCallbackDetails(cb)"
              >
                View
              </button>
            </div>
          </div>

          <!-- Mobile card for callbacks -->
          <div class="tx-card-mobile show-mobile-only">
            <div class="tx-card-left">
              <div class="tx-card-top-row">
                <strong class="mono" style="color: #1e3a8a;">{{ cb.parsed?.mpesaReceiptNumber || 'Receipt N/A' }}</strong>
                <span v-if="cb.parsed?.isSuccess" class="badge paid">● Success</span>
                <span v-else class="badge overdue">● Failed</span>
              </div>
              <p style="font-size: 0.82rem; color: #475467; margin: 4px 0 0;">
                {{ cb.parsed?.matchedTenantName }} · Unit {{ cb.parsed?.matchedUnitNumber }} · {{ cb.parsed?.phoneNumber }}
              </p>
              <span class="tx-card-time">{{ formatHumanDateTime(cb.receivedAt) }}</span>
            </div>
            <div class="tx-card-right">
              <strong class="tx-card-amount">{{ formatKES(cb.parsed?.amount || 0) }}</strong>
            </div>
          </div>
        </div>

        <div v-if="callbacks.length === 0" style="padding: 36px; text-align: center; color: #64748b;">
          No M-Pesa IPN callbacks recorded yet.
        </div>
      </div>
    </section>

    <!-- Manual Reconciliation Slide-Over Side Sheet (Zero Modal Architecture) -->
    <SideSheet
      :open="isReconcileModalOpen && !!txToReconcile"
      title="Manual Payment Reconciliation"
      :subtitle="txToReconcile ? `Assign payment ${txToReconcile.reference} (${formatKES(txToReconcile.amount)}) to resident` : ''"
      width="480px"
      @close="isReconcileModalOpen = false"
    >
      <div v-if="txToReconcile" style="display: flex; flex-direction: column; gap: 16px;">
        <div v-if="reconcileError" class="error-banner">
          <AlertTriangle :size="15" />
          <span>{{ reconcileError }}</span>
        </div>

        <!-- Callback Info Snippet -->
        <div class="callback-snippet">
          <div>
            <span class="sub-label">Remitter: </span>
            <strong class="mono">{{ txToReconcile.payerName || txToReconcile.tenantName }}</strong>
          </div>
          <div>
            <span class="sub-label">Phone: </span>
            <strong class="mono">{{ txToReconcile.phoneNumber }}</strong>
          </div>
          <div>
            <span class="sub-label">Amount: </span>
            <strong class="text-positive mono">{{ formatKES(txToReconcile.amount) }}</strong>
          </div>
        </div>

        <form class="modal-form" @submit.prevent="handleExecuteReconcile">
          <div class="form-group" style="margin-top: 14px;">
            <label>Select Tenant *</label>
            <SearchableSelect
              v-model="selectedTenantId"
              :options="tenantOptions"
              placeholder="Search resident by name or phone..."
              search-placeholder="Type resident name or phone..."
              @change="handleTenantChange"
            />
          </div>

          <div class="form-group">
            <label>Select Mapped Unit *</label>
            <SearchableSelect
              v-model="selectedUnitId"
              :options="unitOptions"
              placeholder="Select apartment unit..."
              search-placeholder="Search unit by number..."
            />
          </div>

          <div class="form-group">
            <label>Reconciliation Note</label>
            <textarea v-model="reconcileNote" rows="2" class="input-field"></textarea>
          </div>

          <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 20px; padding-top: 16px; border-top: 1px solid #eef2f6;">
            <button type="button" class="secondary-button" @click="isReconcileModalOpen = false">
              Cancel
            </button>
            <button type="submit" class="primary-button">
              Confirm & Apply to Ledger
            </button>
          </div>
        </form>
      </div>
    </SideSheet>

    <!-- Payment Detail Side Sheet -->
    <TransactionDetailsSheet
      :open="isDetailsOpen"
      :transaction="selectedTransaction"
      @close="isDetailsOpen = false"
    />

    <!-- Callback Details Side Sheet -->
    <SideSheet
      :open="isCallbackDetailsOpen"
      title="M-Pesa IPN Callback Details"
      :subtitle="selectedCallback?.parsed?.mpesaReceiptNumber ? `Receipt: ${selectedCallback.parsed.mpesaReceiptNumber}` : ''"
      width="540px"
      @close="isCallbackDetailsOpen = false"
    >
      <div v-if="selectedCallback" style="padding: 20px;">
        <div class="summary-box" style="margin-bottom: 18px; padding: 14px 16px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; display: flex; align-items: center; justify-content: space-between;">
          <div>
            <span class="sub-label" style="font-size: 0.78rem; text-transform: uppercase; color: #64748b; font-weight: 600;">Callback Amount</span>
            <div class="amount-display" style="font-size: 1.4rem; font-weight: 700; color: #059669; margin-top: 2px;">
              {{ formatKES(selectedCallback.parsed?.amount || 0) }}
            </div>
          </div>
          <div>
            <span v-if="selectedCallback.parsed?.isSuccess" class="badge paid">
              <CheckCircle2 :size="12" /> Success (0)
            </span>
            <span v-else class="badge overdue">
              <AlertTriangle :size="12" /> Failed
            </span>
          </div>
        </div>

        <div class="section-card" style="margin-bottom: 16px; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px;">
          <h3 class="section-header" style="font-size: 0.88rem; font-weight: 700; color: #0f172a; margin-bottom: 12px; display: flex; align-items: center; gap: 8px;">
            <Smartphone :size="16" />
            <span>Extracted Callback Metadata</span>
          </h3>
          <div class="payload-table" style="display: flex; flex-direction: column; gap: 8px;">
            <div class="payload-row" style="display: flex; justify-content: space-between; border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;">
              <span class="payload-key" style="font-size: 0.80rem; color: #64748b;">M-Pesa Receipt (TransID)</span>
              <strong class="payload-val mono" style="font-size: 0.85rem; color: #1e3a8a;">{{ selectedCallback.parsed?.mpesaReceiptNumber || 'N/A' }}</strong>
            </div>
            <div class="payload-row" style="display: flex; justify-content: space-between; border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;">
              <span class="payload-key" style="font-size: 0.80rem; color: #64748b;">Remitter Mobile Number</span>
              <span class="payload-val mono" style="font-size: 0.85rem; color: #334155;">{{ selectedCallback.parsed?.phoneNumber || 'N/A' }}</span>
            </div>
            <div class="payload-row" style="display: flex; justify-content: space-between; border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;">
              <span class="payload-key" style="font-size: 0.80rem; color: #64748b;">Matched Resident</span>
              <strong class="payload-val" style="font-size: 0.85rem; color: #0f172a;">{{ selectedCallback.parsed?.matchedTenantName || 'Unassigned' }}</strong>
            </div>
            <div class="payload-row" style="display: flex; justify-content: space-between; border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;">
              <span class="payload-key" style="font-size: 0.80rem; color: #64748b;">Assigned Unit</span>
              <span class="payload-val" style="font-size: 0.85rem; color: #0f172a;">Unit {{ selectedCallback.parsed?.matchedUnitNumber || 'None' }}</span>
            </div>
            <div class="payload-row" style="display: flex; justify-content: space-between; border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;">
              <span class="payload-key" style="font-size: 0.80rem; color: #64748b;">Result Description</span>
              <span class="payload-val" style="font-size: 0.82rem; color: #334155;">{{ selectedCallback.parsed?.resultDesc }}</span>
            </div>
            <div class="payload-row" style="display: flex; justify-content: space-between; border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;">
              <span class="payload-key" style="font-size: 0.80rem; color: #64748b;">Received At</span>
              <span class="payload-val mono" style="font-size: 0.78rem; color: #64748b;">{{ selectedCallback.receivedAt }}</span>
            </div>
            <div class="payload-row" style="display: flex; justify-content: space-between; border-bottom: 1px solid #f1f5f9; padding-bottom: 6px;">
              <span class="payload-key" style="font-size: 0.80rem; color: #64748b;">Checkout Request ID</span>
              <span class="payload-val mono" style="font-size: 0.76rem; color: #475569;">{{ selectedCallback.parsed?.checkoutRequestId }}</span>
            </div>
            <div class="payload-row" style="display: flex; justify-content: space-between;">
              <span class="payload-key" style="font-size: 0.80rem; color: #64748b;">Merchant Request ID</span>
              <span class="payload-val mono" style="font-size: 0.76rem; color: #475569;">{{ selectedCallback.parsed?.merchantRequestId }}</span>
            </div>
          </div>
        </div>

        <div class="section-card" style="border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px;">
          <h3 class="section-header" style="font-size: 0.88rem; font-weight: 700; color: #0f172a; margin-bottom: 10px; display: flex; align-items: center; gap: 8px;">
            <FileCode :size="16" />
            <span>Raw IPN JSON Payload (Stored As Received)</span>
          </h3>
          <pre style="background: #0f172a; color: #38bdf8; padding: 14px; border-radius: 8px; font-size: 0.76rem; overflow-x: auto; max-height: 280px; margin: 0;"><code>{{ JSON.stringify(selectedCallback.rawPayload || (selectedCallback.rawString ? JSON.parse(selectedCallback.rawString) : {}), null, 2) }}</code></pre>
        </div>
      </div>
    </SideSheet>
  </div>
</template>

<style scoped>
.unassigned-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px;
  background: #ffffff;
  border: 1px solid #fde68a;
  border-radius: 6px;
  gap: 16px;
  flex-wrap: wrap;
}

.unassigned-details {
  display: flex;
  flex-direction: column;
}

.unassigned-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}

.callback-snippet {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
  padding: 10px 12px;
  background: #f8fafc;
  border: 1px solid #e2e8f0;
  border-radius: 6px;
}

.payments-list-grid {
  grid-template-columns: 140px 1.4fr 130px 140px 140px;
  gap: 12px;
}

.payments-mobile-grid {
  display: grid;
  grid-template-columns: 1.4fr 1.1fr 1fr;
  gap: 8px;
}

.interactive-row {
  cursor: pointer;
  transition: background 0.12s ease;
}

.interactive-row:hover {
  background: #f8fafc;
}

.text-danger {
  color: #dc2626 !important;
}

.text-positive {
  color: #059669 !important;
}



.error-banner {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  border-radius: 6px;
  background: #fef2f2;
  border: 1px solid #fee2e2;
  color: #b91c1c;
  font-size: 0.82rem;
  margin-bottom: 14px;
}

.form-group {
  margin-bottom: 14px;
}

.form-group label {
  display: block;
  font-size: 0.82rem;
  font-weight: 600;
  color: #344054;
  margin-bottom: 5px;
}

.input-field {
  width: 100%;
  padding: 8px 11px;
  border: 1px solid #d0d5dd;
  border-radius: 6px;
  font: inherit;
  font-size: 0.88rem;
  color: #101828;
  box-sizing: border-box;
}

.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  margin-top: 20px;
}
</style>
