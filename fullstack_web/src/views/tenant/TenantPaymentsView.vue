<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { CreditCard, Plus, ChevronRight, FileText } from 'lucide-vue-next'
import {
  store,
  formatKES,
  formatHumanDate,
  formatHumanDateTime,
  getTenantFinancialStanding,
  fetchTenantProfile
} from '../../data'
import { downloadReceiptPdf } from '../../utils/receiptGenerator'
import PaginationControl from '../../components/PaginationControl.vue'
import TransactionDetailsSheet from '../../components/TransactionDetailsSheet.vue'
import TenantStatementSheet from '../../components/TenantStatementSheet.vue'
import type { Transaction } from '../../types'

onMounted(async () => {
  await fetchTenantProfile()
})

const showStatementSheet = ref(false)

const resident = computed(() => {
  return (
    store.tenants.find(t => store.session.email && t.email && t.email.toLowerCase() === store.session.email.toLowerCase()) ||
    store.tenants.find(t => store.session.tenantId && t.id === store.session.tenantId) ||
    store.tenants.find(t => store.session.id && t.id === store.session.id) ||
    null
  )
})

const activeLease = computed(() => {
  if (!resident.value) return null
  return (
    store.leases.find(l => l.tenantId === resident.value?.id && (l.status === 'active' || l.status === 'pending_deposit')) ||
    store.leases.find(l => l.tenantId === resident.value?.id) ||
    null
  )
})

const currentUnit = computed(() => {
  if (!resident.value) return null
  if (activeLease.value?.unitId) {
    const u = store.units.find(u => u.id === activeLease.value?.unitId)
    if (u) return u
  }
  if (resident.value.currentUnitId) {
    const u = store.units.find(u => u.id === resident.value?.currentUnitId)
    if (u) return u
  }
  const unitNum = activeLease.value?.unitNumber || resident.value.currentUnitNumber
  if (unitNum) {
    const u = store.units.find(u => u.unitNumber === unitNum)
    if (u) return u
  }
  return null
})

const standing = computed(() => {
  return getTenantFinancialStanding(resident.value)
})

const transactions = computed(() => {
  if (!resident.value) return []
  return store.transactions.filter(tx => tx.tenantId === resident.value?.id)
})

// Pagination
const currentPage = ref(1)
const pageSize = ref(10)

const paginatedTransactions = computed(() => {
  const start = (currentPage.value - 1) * pageSize.value
  return transactions.value.slice(start, start + pageSize.value)
})

// Transaction details side sheet
const selectedTransaction = ref<Transaction | null>(null)
const isDetailsOpen = ref(false)

function openTransaction(tx: Transaction) {
  selectedTransaction.value = tx
  isDetailsOpen.value = true
}

function downloadTxReceipt(tx: Transaction) {
  const tenant = resident.value
  const lease = activeLease.value
  const st = getTenantFinancialStanding(tenant)
  downloadReceiptPdf(tx, tenant, lease, st)
}
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">RESIDENT LEDGER</p>
        <h1>Rent Payments</h1>
        <p>Complete historical payment ledger for your tenancy at Lapis Suites.</p>
      </div>

      <div class="intro-actions">
        <button type="button" class="secondary-button" @click="showStatementSheet = true">
          <FileText :size="15" />
          <span>Statement</span>
        </button>
        <router-link to="/tenant/pay" class="primary-button">
          <CreditCard :size="15" />
          <span>Make Payment</span>
        </router-link>
      </div>
    </header>

    <!-- Financial Standing Summary Box (Dynamic) -->
    <div class="panel"
      style="padding: 16px 20px; margin-bottom: 20px; display: flex; align-items: center; justify-content: space-between; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 10px; flex-wrap: wrap; gap: 12px;">
      <div>
        <span
          style="font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.05em; color: #64748b; font-weight: 600;">Current
          Account Standing</span>
        <div style="font-size: 1.25rem; font-weight: 700; color: #0f172a; margin-top: 3px;">
          {{ standing.statusText }}
        </div>
        <p style="font-size: 0.82rem; color: #64748b; margin-top: 3px;">
          {{ standing.description }}
        </p>
      </div>
      <!-- <div style="display: flex; align-items: center; gap: 10px; flex-wrap: wrap;">
        <span :class="['badge', standing.badgeClass]" style="font-size: 0.82rem; padding: 6px 12px;">
          {{ standing.badgeText }}
        </span>
        <router-link to="/tenant/pay" class="tx-open-pay-btn">
          <CreditCard :size="14" />
          <span>Pay Online</span>
        </router-link>
      </div> -->
    </div>

    <!-- Transaction Feed Section -->
    <section class="tx-feed-section">
      <div class="tx-feed-header-bar">
        <div class="tx-feed-header-info">
          <h2>Payment Records ({{ transactions.length }})</h2>
          <!-- <p>Chronological receipts matching your tenancy ledger. Click any card for full details.</p> -->
          <p>Click any card for full details.</p>
        </div>
        <router-link to="/tenant/pay" class="tx-open-pay-btn">
          <CreditCard :size="15" />
          <span>Open Payment Link</span>
        </router-link>
      </div>

      <!-- Vertical Stack of Individual Transaction Cards -->
      <div v-if="paginatedTransactions.length > 0" class="tx-feed-stack">
        <div v-for="tx in paginatedTransactions" :key="tx.id" class="tx-feed-card" @click="openTransaction(tx)">
          <!-- Left side: Payment origin badge alongside formatted date & time -->
          <div class="tx-card-left">
            <span v-if="tx.source === 'callback' || tx.reconciledBy?.includes('Webhook') || tx.method === 'stk_push'"
              class="origin-badge badge-mpesa">
              ● M-Pesa
            </span>
            <span v-else-if="tx.method === 'mpesa_paybill'" class="origin-badge badge-mpesa">
              ● M-Pesa Paybill
            </span>
            <span v-else class="origin-badge badge-manual">
              ● Direct Payment
            </span>

            <div class="tx-datetime-container">
              <span class="tx-datetime-text">{{ formatHumanDateTime(tx.timestamp || tx.date) }}</span>
              <span v-if="tx.reference" class="tx-ref-code">{{ tx.reference }}</span>
            </div>
          </div>

          <!-- Right side: Bold amount paired directly with status badge & inline PDF download link -->
          <div class="tx-card-right">
            <strong class="tx-amount">{{ formatKES(tx.amount) }}</strong>

            <div class="tx-right-meta">
              <span :class="['status-badge', tx.status === 'reconciled' ? 'status-reconciled' : 'status-unassigned']">
                ● {{ tx.status === 'reconciled' ? 'Reconciled' : tx.status === 'pending_verification' ? 'Pending Verification' : 'Unassigned' }}
              </span>

              <button type="button" class="tx-pdf-btn" title="Download Official PDF Receipt"
                @click.stop="downloadTxReceipt(tx)">
                <FileText :size="13" />
                <span>PDF</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Clean Empty State -->
      <div v-else class="tx-empty-state">
        <div class="tx-empty-icon-box">
          <FileText :size="24" />
        </div>
        <h3>No payment records found</h3>
        <p>Verified transactions for your tenancy ledger will be cataloged here chronologically.</p>
        <!-- <router-link to="/tenant/pay" class="tx-open-pay-btn">
          <CreditCard :size="15" />
          <span>Open Payment Link</span>
        </router-link> -->
      </div>

      <div style="margin-top: 16px;">
        <PaginationControl v-model:current-page="currentPage" v-model:page-size="pageSize"
          :total-items="transactions.length" />
      </div>
    </section>

    <!-- Full uncollapsed transaction details sheet -->
    <TransactionDetailsSheet :open="isDetailsOpen" :transaction="selectedTransaction" @close="isDetailsOpen = false" />

    <!-- Printable Official Account Statement Sheet -->
    <TenantStatementSheet :open="showStatementSheet" :tenant="resident" @close="showStatementSheet = false" />
  </div>
</template>

<style scoped>
/* Main Feed Container */
.tx-feed-section {
  background-color: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  padding: 24px;
  box-shadow: 0 1px 3px rgba(15, 23, 42, 0.04);
  width: 100%;
  box-sizing: border-box;
}

.tx-feed-header-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
  flex-wrap: wrap;
  gap: 12px;
}

.tx-feed-header-info h2 {
  font-size: 1.15rem;
  font-weight: 700;
  color: #0f172a;
  margin: 0;
}

.tx-feed-header-info p {
  font-size: 0.84rem;
  color: #64748b;
  margin: 4px 0 0 0;
}

.tx-open-pay-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background-color: #0f172a;
  color: #ffffff;
  font-size: 0.82rem;
  font-weight: 600;
  padding: 8px 14px;
  border-radius: 6px;
  text-decoration: none;
  border: 1px solid #0f172a;
  transition: background-color 0.15s ease, border-color 0.15s ease;
}

.tx-open-pay-btn:hover {
  background-color: #1e293b;
  border-color: #1e293b;
  color: #ffffff;
}

/* Vertical Stack of Individual Cards */
.tx-feed-stack {
  display: flex;
  flex-direction: column;
  gap: 12px;
  width: 100%;
}

/* Individual Transaction Card */
.tx-feed-card {
  display: flex;
  justify-content: space-between;
  align-items: center;
  background-color: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 10px;
  padding: 14px 18px;
  box-shadow: 0 1px 3px rgba(15, 23, 42, 0.04);
  cursor: pointer;
  transition: transform 0.15s ease, box-shadow 0.15s ease, border-color 0.15s ease;
}

.tx-feed-card:hover {
  border-color: #cbd5e1;
  box-shadow: 0 4px 12px rgba(15, 23, 42, 0.08);
  transform: translateY(-1px);
}

/* Left Side: Origin Badge + Formatted Date and Time */
.tx-card-left {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}

.origin-badge {
  display: inline-flex;
  align-items: center;
  padding: 4px 9px;
  border-radius: 16px;
  font-size: 0.73rem;
  font-weight: 600;
  white-space: nowrap;
}

.badge-mpesa {
  background-color: #ecfdf5;
  color: #047857;
  border: 1px solid #a7f3d0;
}

.badge-manual {
  background-color: #f1f5f9;
  color: #475569;
  border: 1px solid #cbd5e1;
}

.tx-datetime-container {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.tx-datetime-text {
  font-size: 0.85rem;
  color: #334155;
  font-weight: 500;
}

.tx-ref-code {
  font-family: "Google Sans Code", monospace;
  font-size: 0.74rem;
  color: #64748b;
  background-color: #f8fafc;
  border: 1px solid #e2e8f0;
  padding: 2px 6px;
  border-radius: 4px;
}

/* Right Side: Bold Amount + Status Badge + Inline PDF Link */
.tx-card-right {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-shrink: 0;
}

.tx-right-meta {
  display: flex;
  align-items: center;
  gap: 8px;
}

.tx-amount {
  font-size: 0.98rem;
  font-weight: 700;
  color: #059669;
  font-family: "Google Sans Flex", "Google Sans", sans-serif;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}

.status-badge {
  display: inline-flex;
  align-items: center;
  padding: 4px 9px;
  border-radius: 16px;
  font-size: 0.73rem;
  font-weight: 600;
  white-space: nowrap;
}

.status-reconciled {
  background-color: #ecfdf5;
  color: #047857;
  border: 1px solid #a7f3d0;
}

.status-unassigned {
  background-color: #fffbeb;
  color: #b45309;
  border: 1px solid #fde68a;
}

.tx-pdf-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px 9px;
  height: 28px;
  font-size: 0.74rem;
  font-weight: 600;
  color: #334155;
  background-color: #f8fafc;
  border: 1px solid #cbd5e1;
  border-radius: 6px;
  cursor: pointer;
  text-decoration: none;
  transition: background-color 0.15s ease, border-color 0.15s ease, color 0.15s ease;
}

.tx-pdf-btn:hover {
  background-color: #f1f5f9;
  border-color: #94a3b8;
  color: #0f172a;
}

/* Empty State */
.tx-empty-state {
  padding: 44px 20px;
  text-align: center;
  background-color: #f8fafc;
  border: 1px dashed #cbd5e1;
  border-radius: 10px;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.tx-empty-icon-box {
  display: inline-flex;
  padding: 12px;
  background-color: #ffffff;
  border-radius: 50%;
  color: #64748b;
  margin-bottom: 12px;
  border: 1px solid #e2e8f0;
  box-shadow: 0 1px 3px rgba(15, 23, 42, 0.05);
}

.tx-empty-state h3 {
  font-size: 0.95rem;
  font-weight: 600;
  color: #1e293b;
  margin: 0 0 6px 0;
}

.tx-empty-state p {
  font-size: 0.84rem;
  color: #64748b;
  margin: 0 0 16px 0;
  max-width: 440px;
}

/* Compact Horizontal Mobile Row (No Awkward Vertical Column Stacking) */
@media (max-width: 680px) {
  .tx-feed-section {
    padding: 16px 14px;
  }

  .tx-feed-stack {
    gap: 9px;
  }

  .tx-feed-card {
    flex-direction: row;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 12px 13px;
  }

  .tx-card-left {
    flex-direction: column;
    align-items: flex-start;
    gap: 4px;
    min-width: 0;
    flex: 1;
  }

  .origin-badge {
    font-size: 0.68rem;
    padding: 2px 7px;
  }

  .tx-datetime-container {
    flex-direction: column;
    align-items: flex-start;
    gap: 3px;
    min-width: 0;
    max-width: 100%;
  }

  .tx-datetime-text {
    font-size: 0.77rem;
    color: #475569;
    line-height: 1.25;
  }

  .tx-ref-code {
    font-size: 0.69rem;
    padding: 1px 5px;
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .tx-card-right {
    flex-direction: column;
    align-items: flex-end;
    gap: 5px;
    flex-shrink: 0;
  }

  .tx-amount {
    font-size: 0.94rem;
    line-height: 1.15;
  }

  .tx-right-meta {
    gap: 5px;
  }

  .status-badge {
    font-size: 0.67rem;
    padding: 2px 7px;
  }

  .tx-pdf-btn {
    height: 24px;
    padding: 2px 7px;
    font-size: 0.69rem;
  }
}
</style>
