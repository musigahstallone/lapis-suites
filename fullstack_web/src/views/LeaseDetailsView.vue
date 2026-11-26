<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  Building2,
  ArrowLeft,
  AlertTriangle,
  ShieldCheck,
  FileText,
  CreditCard
} from 'lucide-vue-next'
import {
  store,
  formatKES,
  formatHumanDate,
  formatHumanDateTime,
  terminateLease,
  isDepositVerifiedPaid,
  fetchLeases,
  getTenantFinancialStanding
} from '../data'
import SideSheet from '../components/SideSheet.vue'
import TransactionDetailsSheet from '../components/TransactionDetailsSheet.vue'
import { downloadReceiptPdf } from '../utils/receiptGenerator'
import type { Transaction } from '../types'

const route = useRoute()

const leaseId = computed(() => route.params.id as string)
const lease = computed(() => store.leases.find(l => l.id === leaseId.value || l.leaseNumber?.toLowerCase() === leaseId.value?.toLowerCase()))

onMounted(async () => {
  await fetchLeases()
})

const unit = computed(() => {
  if (!lease.value) return null
  return store.units.find(u => u.id === lease.value?.unitId) || null
})

const tenant = computed(() => {
  if (!lease.value) return null
  return store.tenants.find(t => t.id === lease.value?.tenantId) || null
})

const showTerminateConfirm = ref(false)

const leaseTransactions = computed(() => {
  if (!lease.value) return []
  return store.transactions.filter(t => 
    t.leaseId === lease.value?.id || 
    (t.tenantId === lease.value?.tenantId && t.unitNumber === lease.value?.unitNumber)
  ).sort((a, b) => new Date(b.timestamp || b.date).getTime() - new Date(a.timestamp || a.date).getTime())
})

const selectedTransaction = ref<Transaction | null>(null)
const isDetailsOpen = ref(false)

function openTransaction(tx: Transaction) {
  selectedTransaction.value = tx
  isDetailsOpen.value = true
}

function handleDownloadReceipt(tx: Transaction) {
  const st = tenant.value ? getTenantFinancialStanding(tenant.value) : null
  downloadReceiptPdf(tx, tenant.value, lease.value, st)
}

async function handleTerminate() {
  if (!lease.value) return
  await terminateLease(lease.value.id)
  showTerminateConfirm.value = false
}
</script>

<template>
  <div v-if="lease" class="page-body">
    <!-- Breadcrumb & Status -->
    <div class="breadcrumb-bar">
      <router-link to="/leases" class="back-link">
        <ArrowLeft :size="16" />
        <span>Back to Leases</span>
      </router-link>
      <span :class="['badge', lease.status]">● {{ lease.status }}</span>
    </div>

    <!-- Page Header -->
    <header class="page-intro" style="margin-bottom: 24px;">
      <div>
        <p class="eyebrow">RESIDENTIAL LEASE AGREEMENT</p>
        <div style="display: flex; align-items: center; gap: 10px; flex-wrap: wrap;">
          <h1 style="margin: 0;">{{ lease.leaseNumber }}</h1>
          <span :class="['badge', lease.status]" style="text-transform: capitalize; font-size: 0.82rem; padding: 4px 10px;">
            ● {{ lease.status.replace('_', ' ') }}
          </span>
        </div>
        <p style="margin-top: 6px;">Agreement between Lapis Suites and {{ lease.tenantName }} for Unit {{ lease.unitNumber }}.</p>
      </div>

      <div class="intro-actions">
        <button
          v-if="lease.status === 'active'"
          type="button"
          class="secondary-button"
          style="color: #b91c1c; border-color: #fecaca;"
          @click="showTerminateConfirm = true"
        >
          <AlertTriangle :size="15" />
          <span>Terminate Agreement</span>
        </button>
      </div>
    </header>

    <!-- Essential Financials Grid -->
    <section class="stats-grid" style="margin-bottom: 24px;">
      <article class="stat-card">
        <div class="stat-label">Agreed Monthly Rent</div>
        <div class="stat-value text-positive">
          {{ formatKES(lease.monthlyRent) }}
        </div>
        <div class="stat-trend positive">
          <span>Standard monthly billing rate</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Security Deposit Status</div>
        <div class="stat-value" :class="isDepositVerifiedPaid(lease) ? 'text-positive' : 'text-danger'" style="font-size: 1.3rem;">
          {{ isDepositVerifiedPaid(lease) ? 'Paid (Audited)' : 'Pending Deposit' }}
        </div>
        <div class="stat-trend" :class="isDepositVerifiedPaid(lease) ? 'positive' : 'negative'">
          <span>{{ formatKES(lease.depositAmount) }} escrow deposit requirement</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Next Payment Due Date</div>
        <div class="stat-value mono" style="font-size: 1.35rem;">
          {{ lease.nextPaymentDueDate ? formatHumanDate(lease.nextPaymentDueDate) : '5th of month' }}
        </div>
        <div class="stat-trend neutral">
          <span>Due on the 5th of each month</span>
        </div>
      </article>
    </section>

    <!-- Details Grid -->
    <div class="details-grid">
      <!-- Unit & Tenant Information -->
      <section class="card-panel">
        <div class="panel-section-title">
          <Building2 :size="16" />
          <h2>Tenancy Parties & Premises</h2>
        </div>

        <div class="spec-grid">
          <div class="spec-item">
            <span class="spec-label">Leased Unit</span>
            <strong class="spec-value">
              <router-link v-if="unit" :to="`/units/${unit.id}`" class="text-link">
                Unit {{ lease.unitNumber }} ({{ lease.unitType }})
              </router-link>
              <span v-else>Unit {{ lease.unitNumber }}</span>
            </strong>
          </div>

          <div class="spec-item">
            <span class="spec-label">Assigned Resident</span>
            <strong class="spec-value">
              <router-link v-if="tenant" :to="`/tenants/${tenant.id}`" class="text-link">
                {{ lease.tenantName }}
              </router-link>
              <span v-else>{{ lease.tenantName }}</span>
            </strong>
          </div>

          <div class="spec-item">
            <span class="spec-label">Commencement Date</span>
            <strong class="spec-value mono">{{ formatHumanDate(lease.startDate) }}</strong>
          </div>

          <div class="spec-item">
            <span class="spec-label">Expiration Date</span>
            <strong class="spec-value mono">{{ formatHumanDate(lease.endDate) }}</strong>
          </div>
        </div>
      </section>

      <!-- Terms & Move-In Financials -->
      <section class="card-panel">
        <div class="panel-section-title">
          <ShieldCheck :size="16" />
          <h2>Agreement Terms</h2>
        </div>

        <div style="font-size: 0.88rem; line-height: 1.5; color: #334155;">
          <p>{{ lease.terms }}</p>

          <div v-if="lease.transferNotes" class="transfer-notes-box">
            <strong>Transfer Record:</strong>
            <p>{{ lease.transferNotes }}</p>
          </div>
        </div>
      </section>
    </div>

    <!-- Comprehensive Lease Payment Records & Ledger -->
    <section class="structured-panel" style="margin-top: 24px;">
      <div class="panel-header-bar" style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 10px;">
        <div class="panel-header-title">
          <h2>Lease Payments Ledger ({{ leaseTransactions.length }})</h2>
          <p>Verified receipts and billing transactions contracted under Lease {{ lease.leaseNumber }}.</p>
        </div>
        <router-link to="/payments/record" class="secondary-button" style="font-size: 0.82rem; padding: 6px 12px;">
          <CreditCard :size="14" />
          <span>Record Payment</span>
        </router-link>
      </div>

      <div v-if="leaseTransactions.length > 0" class="table-responsive-wrapper">
        <div class="list-group-header" style="grid-template-columns: 140px 1.2fr 160px 140px 130px 90px; min-width: 780px;">
          <span>Reference</span>
          <span>Payment Allocation / Note</span>
          <span>Date & Time</span>
          <span>Method</span>
          <span>Amount</span>
          <span style="text-align: right;">Action</span>
        </div>

        <div
          v-for="tx in leaseTransactions"
          :key="tx.id"
          class="list-group-row"
          style="grid-template-columns: 140px 1.2fr 160px 140px 130px 90px; min-width: 780px; cursor: pointer;"
          @click="openTransaction(tx)"
        >
          <div class="list-cell primary-row">
            <strong class="mono" style="font-size: 0.86rem; color: #0f172a;">{{ tx.reference }}</strong>
          </div>

          <div class="list-cell">
            <span style="font-size: 0.84rem; color: #334155;">{{ tx.notes || 'Rent payment' }}</span>
          </div>

          <div class="list-cell">
            <small class="mono" style="color: #64748b;">{{ formatHumanDateTime(tx.timestamp || tx.date) }}</small>
          </div>

          <div class="list-cell">
            <span v-if="tx.source === 'callback' || tx.reconciledBy?.includes('Webhook') || tx.method === 'stk_push'" class="badge" style="background: #ecfdf5; color: #047857; border: 1px solid #a7f3d0; font-size: 0.72rem;">
              ● M-Pesa
            </span>
            <span v-else class="badge" style="background: #f1f5f9; color: #475569; border: 1px solid #cbd5e1; font-size: 0.72rem;">
              ● Direct Payment
            </span>
          </div>

          <div class="list-cell">
            <strong style="color: #059669; font-size: 0.92rem;">{{ formatKES(tx.amount) }}</strong>
          </div>

          <div class="list-cell" style="justify-content: flex-end; gap: 6px;">
            <button
              type="button"
              class="secondary-button"
              style="padding: 3px 8px; font-size: 0.74rem; height: 26px;"
              title="Download PDF Receipt"
              @click.stop="handleDownloadReceipt(tx)"
            >
              <FileText :size="12" />
              <span>PDF</span>
            </button>
          </div>
        </div>
      </div>

      <div v-else style="padding: 36px; text-align: center; color: #64748b;">
        No payment records found for this lease agreement yet.
      </div>
    </section>

    <!-- Full Transaction Details Side Sheet -->
    <TransactionDetailsSheet
      :open="isDetailsOpen"
      :transaction="selectedTransaction"
      @close="isDetailsOpen = false"
    />

    <!-- Termination Confirmation Slide-Over Side Sheet (Zero Modal Architecture) -->
    <SideSheet
      :open="showTerminateConfirm"
      title="Confirm Agreement Termination"
      subtitle="Lease lifecycle management"
      width="440px"
      @close="showTerminateConfirm = false"
    >
      <div v-if="lease" style="display: flex; flex-direction: column; gap: 16px;">
        <p style="font-size: 0.88rem; color: #475467; line-height: 1.5; margin: 0;">
          Are you sure you want to terminate agreement <strong>{{ lease.leaseNumber }}</strong>?
          This will set Unit {{ lease.unitNumber }} to vacant and unbind the active tenancy.
        </p>

        <div style="background: #fef2f2; border: 1px solid #fecaca; border-radius: 6px; padding: 12px; font-size: 0.82rem; color: #991b1b;">
          <strong>Warning:</strong> Terminating this lease will update Unit {{ lease.unitNumber }} status to vacant and release resident {{ lease.tenantName }}.
        </div>

        <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 20px; padding-top: 16px; border-top: 1px solid #eef2f6;">
          <button type="button" class="secondary-button" @click="showTerminateConfirm = false">
            Cancel
          </button>
          <button
            type="button"
            class="primary-button"
            style="background: #dc2626; color: #ffffff;"
            @click="handleTerminate"
          >
            Confirm Termination
          </button>
        </div>
      </div>
    </SideSheet>
  </div>

  <div v-else class="page-body">
    <div style="padding: 40px; text-align: center;">
      <p>Lease not found.</p>
      <router-link to="/leases" class="primary-button" style="display: inline-flex; margin-top: 14px;">
        Back to Leases
      </router-link>
    </div>
  </div>
</template>

<style scoped>
.breadcrumb-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16px;
}

.back-link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 0.84rem;
  font-weight: 500;
  color: #64748b;
  text-decoration: none;
}

.back-link:hover {
  color: #0f172a;
}

.card-panel {
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  padding: 20px;
}

.details-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
}

.panel-section-title {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 16px;
  color: #0f172a;
}

.panel-section-title h2 {
  font-size: 1.05rem;
  font-weight: 700;
  margin: 0;
}

.spec-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 16px;
}

.spec-item {
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.spec-label {
  font-size: 0.74rem;
  color: #64748b;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  font-weight: 600;
}

.spec-value {
  font-size: 0.94rem;
  color: #0f172a;
}

.text-positive {
  color: #059669 !important;
}

.text-link {
  color: #2563eb;
  text-decoration: none;
}

.text-link:hover {
  text-decoration: underline;
}

.transfer-notes-box {
  margin-top: 14px;
  padding: 10px 12px;
  background: #f8fafc;
  border-left: 3px solid #2563eb;
  border-radius: 4px;
  font-size: 0.82rem;
}

.transfer-notes-box strong {
  display: block;
  color: #0f172a;
  margin-bottom: 2px;
}

.transfer-notes-box p {
  margin: 0;
  color: #64748b;
}



@media (max-width: 800px) {
  .details-grid {
    grid-template-columns: 1fr;
  }
}
</style>
