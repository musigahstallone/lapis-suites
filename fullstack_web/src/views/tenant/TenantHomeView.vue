<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import {
  FileText,
  CreditCard,
  ChevronRight
} from 'lucide-vue-next'
import {
  store,
  formatKES,
  getUnitMonthlyRent,
  formatHumanDate,
  formatHumanDateTime,
  getTenantFinancialStanding,
  fetchTenantProfile
} from '../../data'
import { downloadReceiptPdf } from '../../utils/receiptGenerator'
import TransactionDetailsSheet from '../../components/TransactionDetailsSheet.vue'
import type { Transaction } from '../../types'

const router = useRouter()

onMounted(async () => {
  await fetchTenantProfile()
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

const resident = computed(() => {
  return (
    store.tenants.find(t => t.id === store.session.tenantId || t.id === store.session.id) ||
    store.tenants.find(t => t.email && store.session.email && t.email.toLowerCase() === store.session.email.toLowerCase()) ||
    store.tenants.find(t => store.session.name && t.name && t.name.toLowerCase().includes(store.session.name.toLowerCase())) ||
    store.tenants[0]
  )
})

const activeLease = computed(() => {
  if (!resident.value) return null
  return (
    store.leases.find(l => (l.tenantId === resident.value?.id || l.tenantName?.toLowerCase() === resident.value?.name?.toLowerCase()) && (l.status === 'active' || l.status === 'pending_deposit')) ||
    store.leases.find(l => (resident.value?.currentUnitNumber && l.unitNumber === resident.value?.currentUnitNumber)) ||
    store.leases.find(l => l.tenantId === resident.value?.id) ||
    null
  )
})

const currentUnit = computed(() => {
  if (!resident.value) return null
  if (resident.value.currentUnitId) {
    const u = store.units.find(u => u.id === resident.value?.currentUnitId)
    if (u) return u
  }
  if (activeLease.value?.unitId) {
    const u = store.units.find(u => u.id === activeLease.value?.unitId)
    if (u) return u
  }
  const unitNum = resident.value.currentUnitNumber || activeLease.value?.unitNumber || store.session.unitNumber
  if (unitNum) {
    const u = store.units.find(u => u.unitNumber === unitNum)
    if (u) return u
  }
  return null
})

const standing = computed(() => {
  return getTenantFinancialStanding(resident.value)
})

const recentTransactions = computed(() => {
  if (!resident.value) return []
  return store.transactions
    .filter(tx => tx.tenantId === resident.value?.id || (activeLease.value && tx.leaseId === activeLease.value.id) || (currentUnit.value && tx.unitNumber === currentUnit.value.unitNumber))
    .slice(0, 4)
})

const tenantMaintenanceCount = computed(() => {
  if (!resident.value) return 0
  return store.maintenanceRequests.filter(m => m.tenantId === resident.value?.id && m.status !== 'resolved').length
})
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">RESIDENT DASHBOARD</p>
        <h1>Welcome home, {{ resident?.name?.split(' ')[0] || 'Resident' }} 👋</h1>
        <!-- <p v-if="currentUnit">Suite {{ currentUnit?.unitNumber }} · Floor {{ currentUnit?.floor || 1 }} · Lapis Suites</p>
        <p v-else>No Suite Assigned · Lapis Suites Resident</p> -->
      </div>

      <div class="intro-actions" style="display: flex; gap: 8px;">
        <router-link to="/tenant/maintenance" class="secondary-button">
          <span>Maintenance</span>
          <span v-if="tenantMaintenanceCount > 0" class="nav-badge" style="background: #ea580c; color: white;">{{ tenantMaintenanceCount }}</span>
        </router-link>
        <router-link to="/tenant/pay" class="primary-button">
          <CreditCard :size="15" />
          <span>Pay Rent</span>
        </router-link>
      </div>
    </header>

    <!-- Top Summary Cards (60-30-10 Disciplined Styling) -->
    <section class="tenant-summary" style="margin-bottom: 22px;">
      <!-- Next Rent Payment / Rent Status (Strictly Dynamic Calculation) -->
      <article class="stat-card" style="display: flex; flex-direction: column; justify-content: space-between;">
        <div>
          <div style="display: flex; align-items: center; justify-content: space-between;">
            <span class="stat-label">Rent Status</span>
            <!-- Status Badge -->
            <span :class="['badge', standing.badgeClass]" style="font-size: 0.76rem;">
              {{ standing.badgeText }}
            </span>
          </div>

          <!-- Prominent Primary Figure -->
          <div class="stat-value" style="margin-top: 8px; font-size: 1.5rem;">
            {{ standing.statusText }}
          </div>

          <!-- Clean Human Status Sentence -->
          <p style="font-size: 0.82rem; color: #64748b; margin-top: 5px;">
            {{ standing.description }}
          </p>
        </div>

        <div style="margin-top: 18px;">
          <router-link to="/tenant/pay" class="primary-button" style="width: 100%;">
            {{ standing.balance > 0 ? 'Pay Arrears Now' : 'Make Advance Payment' }} <ChevronRight :size="14" />
          </router-link>
        </div>
      </article>

      <!-- Active Lease -->
      <article class="stat-card" style="display: flex; flex-direction: column; justify-content: space-between;">
        <div v-if="activeLease">
          <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px;">
            <span class="stat-label">Active Agreement</span>
            <span class="badge active">{{ activeLease?.leaseNumber || 'Active' }}</span>
          </div>
          <h2 style="font-size: 1.15rem; font-weight: 700; color: #172033; margin: 4px 0 2px;">
            Unit {{ currentUnit?.unitNumber || activeLease?.unitNumber || resident?.currentUnitNumber }} ({{ currentUnit?.type || activeLease?.unitType || 'Suite' }})
          </h2>
          <p style="font-size: 0.82rem; color: #64748b;">
            Expires {{ activeLease?.endDate }} · {{ formatKES(activeLease?.monthlyRent || (currentUnit ? getUnitMonthlyRent(currentUnit) : 0)) }}/mo
          </p>
        </div>
        <div v-else>
          <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px;">
            <span class="stat-label">Agreement Status</span>
            <span class="badge vacant">No Active Agreement</span>
          </div>
          <h2 style="font-size: 1.05rem; font-weight: 700; color: #172033; margin: 4px 0 2px;">
            No Unit Assigned
          </h2>
          <p style="font-size: 0.82rem; color: #64748b;">
            Contact property management to assign your residential lease agreement.
          </p>
        </div>

        <div style="margin-top: 18px;">
          <router-link to="/tenant/documents" class="secondary-button" style="width: 100%;">
            <FileText :size="14" /> View Lease Document
          </router-link>
        </div>
      </article>
    </section>

    <!-- Recent Payments List Group -->
    <section class="structured-panel">
      <div class="panel-header-bar">
        <div class="panel-header-title">
          <h2>Recent Payment History</h2>
          <p>Verified transactions for your tenancy at Lapis Suites. Click any row for details.</p>
        </div>
        <router-link to="/tenant/payments" class="text-button" style="font-size: 0.82rem;">
          View all <ChevronRight :size="14" />
        </router-link>
      </div>

      <!-- Modern Vertical Stack of Individual Transaction Cards -->
      <div v-if="recentTransactions.length > 0" class="tx-home-feed-stack">
        <div
          v-for="tx in recentTransactions"
          :key="tx.id"
          class="tx-home-feed-card"
          @click="openTransaction(tx)"
        >
          <!-- Left side: Payment origin badge alongside formatted date & time -->
          <div class="tx-home-card-left">
            <span
              v-if="tx.source === 'callback' || tx.reconciledBy?.includes('Webhook') || tx.method === 'stk_push'"
              class="tx-origin-badge badge-mpesa"
            >
              ● M-Pesa Callback
            </span>
            <span
              v-else-if="tx.method === 'mpesa_paybill'"
              class="tx-origin-badge badge-mpesa"
            >
              ● M-Pesa Paybill
            </span>
            <span
              v-else
              class="tx-origin-badge badge-manual"
            >
              ● Manual Entry
            </span>

            <div class="tx-datetime-container">
              <span class="tx-datetime-text">{{ formatHumanDateTime(tx.timestamp || tx.date) }}</span>
              <span v-if="tx.reference" class="tx-ref-code">{{ tx.reference }}</span>
            </div>
          </div>

          <!-- Right side: Bold amount paired directly with status badge & inline PDF download link -->
          <div class="tx-home-card-right">
            <strong class="tx-home-amount">{{ formatKES(tx.amount) }}</strong>

            <div class="tx-home-right-meta">
              <span
                :class="['tx-status-badge', tx.status === 'reconciled' ? 'status-reconciled' : 'status-unassigned']"
              >
                ● {{ tx.status === 'reconciled' ? 'Reconciled' : tx.status === 'pending_verification' ? 'Pending Verification' : 'Unassigned' }}
              </span>

              <button
                type="button"
                class="tx-home-pdf-btn"
                title="Download Official PDF Receipt"
                @click.stop="downloadTxReceipt(tx)"
              >
                <FileText :size="13" />
                <span>PDF</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <div v-if="recentTransactions.length === 0" style="padding: 24px; text-align: center; color: #64748b;">
        No payment records found.
      </div>
    </section>

    <TransactionDetailsSheet
      :open="isDetailsOpen"
      :transaction="selectedTransaction"
      @close="isDetailsOpen = false"
    />
  </div>
</template>

<style scoped>
/* Modern Vertical Stack of Cards */
.tx-home-feed-stack {
  display: flex;
  flex-direction: column;
  gap: 10px;
  width: 100%;
}

.tx-home-feed-card {
  display: flex;
  justify-content: space-between;
  align-items: center;
  background-color: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 10px;
  padding: 12px 16px;
  box-shadow: 0 1px 3px rgba(15, 23, 42, 0.04);
  cursor: pointer;
  transition: transform 0.15s ease, box-shadow 0.15s ease, border-color 0.15s ease;
}

.tx-home-feed-card:hover {
  border-color: #cbd5e1;
  box-shadow: 0 4px 12px rgba(15, 23, 42, 0.08);
  transform: translateY(-1px);
}

.tx-home-card-left {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}

.tx-origin-badge {
  display: inline-flex;
  align-items: center;
  padding: 3px 8px;
  border-radius: 16px;
  font-size: 0.72rem;
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
  font-size: 0.84rem;
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

.tx-home-card-right {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-shrink: 0;
}

.tx-home-right-meta {
  display: flex;
  align-items: center;
  gap: 8px;
}

.tx-home-amount {
  font-size: 0.95rem;
  font-weight: 700;
  color: #059669;
  font-family: "Google Sans Flex", "Google Sans", sans-serif;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}

.tx-status-badge {
  display: inline-flex;
  align-items: center;
  padding: 3px 8px;
  border-radius: 16px;
  font-size: 0.72rem;
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

.tx-home-pdf-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 8px;
  height: 26px;
  font-size: 0.73rem;
  font-weight: 600;
  color: #334155;
  background-color: #f8fafc;
  border: 1px solid #cbd5e1;
  border-radius: 6px;
  cursor: pointer;
  text-decoration: none;
  transition: background-color 0.15s ease, border-color 0.15s ease, color 0.15s ease;
}

.tx-home-pdf-btn:hover {
  background-color: #f1f5f9;
  border-color: #94a3b8;
  color: #0f172a;
}

@media (max-width: 680px) {
  .tx-home-feed-card {
    flex-direction: row;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 11px 13px;
  }

  .tx-home-card-left {
    flex-direction: column;
    align-items: flex-start;
    gap: 4px;
    min-width: 0;
    flex: 1;
  }

  .tx-origin-badge {
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
    font-size: 0.76rem;
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

  .tx-home-card-right {
    flex-direction: column;
    align-items: flex-end;
    gap: 5px;
    flex-shrink: 0;
  }

  .tx-home-amount {
    font-size: 0.92rem;
    line-height: 1.15;
  }

  .tx-home-right-meta {
    gap: 5px;
  }

  .tx-status-badge {
    font-size: 0.67rem;
    padding: 2px 7px;
  }

  .tx-home-pdf-btn {
    height: 24px;
    padding: 2px 7px;
    font-size: 0.69rem;
  }
}
</style>
