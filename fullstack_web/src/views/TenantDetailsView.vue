<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  Users,
  Building2,
  ArrowLeft,
  ArrowRightLeft,
  AlertCircle,
  FileText,
  RefreshCw,
  CheckCircle2
} from 'lucide-vue-next'
import {
  store,
  formatKES,
  formatHumanDate,
  getUnitMonthlyRent,
  getTenantFinancialStanding,
  fetchTenants,
  fetchUnits,
  fetchLeases,
  reconcileTenantLedger
} from '../data'
import TenantStatementSheet from '../components/TenantStatementSheet.vue'

const showStatementSheet = ref(false)
const isReconciling = ref(false)
const reconcileMessage = ref('')

async function handleReconcile() {
  if (!tenant.value) return
  isReconciling.value = true
  reconcileMessage.value = ''
  try {
    const res = await reconcileTenantLedger(tenant.value.id)
    reconcileMessage.value = `Ledger successfully reconciled! Security Deposit: ${res.summary.depositPaid ? '100% Satisfied' : 'Pending'} · Next Due: ${formatHumanDate(res.summary.nextPaymentDueDate)} · ${res.summary.accountCredit > 0 ? `Credit Balance: ${formatKES(res.summary.accountCredit)}` : (res.summary.balance > 0 ? `Arrears: ${formatKES(res.summary.balance)}` : 'Account Settled')}`
    setTimeout(() => {
      reconcileMessage.value = ''
    }, 7000)
  } catch (err: any) {
    alert(err.message || 'Failed to reconcile tenant ledger')
  } finally {
    isReconciling.value = false
  }
}

const route = useRoute()
const router = useRouter()

const tenantId = computed(() => route.params.id as string)
const tenant = computed(() => store.tenants.find(t => t.id === tenantId.value || t.email?.toLowerCase() === tenantId.value?.toLowerCase()))

onMounted(async () => {
  await Promise.all([fetchTenants(), fetchUnits(), fetchLeases()])
})

const standing = computed(() => getTenantFinancialStanding(tenant.value))

const activeLease = computed(() => {
  if (!tenant.value) return null
  if (tenant.value.currentLeaseId) {
    const l = store.leases.find(l => l.id === tenant.value?.currentLeaseId)
    if (l) return l
  }
  return (
    store.leases.find(l => l.tenantId === tenant.value?.id && (l.status === 'active' || l.status === 'pending_deposit')) ||
    store.leases.find(l => l.tenantId === tenant.value?.id) ||
    null
  )
})

const currentUnit = computed(() => {
  if (!tenant.value) return null
  if (tenant.value.currentUnitId) {
    const u = store.units.find(u => u.id === tenant.value?.currentUnitId)
    if (u) return u
  }
  if (activeLease.value?.unitId) {
    const u = store.units.find(u => u.id === activeLease.value?.unitId)
    if (u) return u
  }
  const unitNum = tenant.value.currentUnitNumber || activeLease.value?.unitNumber
  if (unitNum) {
    const u = store.units.find(u => u.unitNumber === unitNum)
    if (u) return u
  }
  return null
})
</script>

<template>
  <div v-if="tenant" class="page-body">
    <!-- Top Breadcrumb & Status -->
    <div class="breadcrumb-bar">
      <router-link to="/tenants" class="back-link">
        <ArrowLeft :size="16" />
        <span>Back to Tenants</span>
      </router-link>
      <span :class="['badge', tenant.status]">● {{ tenant.status }}</span>
    </div>

    <!-- Page Intro Header -->
    <header class="page-intro" style="margin-bottom: 24px;">
      <div>
        <p class="eyebrow">RESIDENT PROFILE</p>
        <h1>{{ tenant.name }}</h1>
        <p>
          <span v-if="currentUnit">Resident of Unit {{ currentUnit.unitNumber }} ({{ currentUnit.type }})</span>
          <span v-else>No active unit assigned</span>
          · Moved in {{ formatHumanDate(tenant.moveInDate) }}
        </p>
      </div>

      <div class="intro-actions">
        <button
          type="button"
          class="secondary-button"
          style="display: inline-flex; align-items: center; gap: 6px; font-weight: 600;"
          :disabled="isReconciling"
          @click="handleReconcile"
        >
          <RefreshCw :size="15" :style="isReconciling ? 'animation: spin 1s linear infinite;' : ''" />
          <span>{{ isReconciling ? 'Reconciling...' : 'Reconcile Ledger' }}</span>
        </button>
        <button
          type="button"
          class="secondary-button"
          @click="showStatementSheet = true"
        >
          <FileText :size="15" />
          <span>Statement</span>
        </button>
        <router-link
          :to="`/tenants/${tenant.id}/lease-changes`"
          class="primary-button"
        >
          <ArrowRightLeft :size="15" />
          <span>{{ currentUnit ? 'Lease Changes & Transfer' : 'Assign Unit / Lease' }}</span>
        </router-link>
      </div>
    </header>

    <!-- Reconciliation Confirmation Banner -->
    <div
      v-if="reconcileMessage"
      style="margin-bottom: 20px; padding: 14px 18px; background: #ecfdf5; border: 1px solid #a7f3d0; border-radius: 8px; color: #047857; display: flex; align-items: center; gap: 10px; font-size: 0.88rem; font-weight: 500;"
    >
      <CheckCircle2 :size="18" style="flex: none; color: #059669;" />
      <span>{{ reconcileMessage }}</span>
    </div>

    <!-- Top Stats Row: Ledger & Financial Standing (Strictly Dynamic Calculation) -->
    <section class="stats-grid" style="margin-bottom: 24px;">
      <article class="stat-card">
        <div class="stat-label">Net Ledger Standing</div>
        <div
          class="stat-value"
          :class="standing.balance > 0 ? 'text-danger' : 'text-positive'"
        >
          {{ standing.statusText }}
        </div>
        <div class="stat-trend" :class="standing.balance > 0 ? 'negative' : 'positive'">
          <span>{{ standing.balance > 0 ? 'Outstanding overdue arrears' : (standing.accountCredit > 0 ? 'Surplus credit on ledger' : 'Account all paid up') }}</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Advance Rent Credit</div>
        <div class="stat-value text-positive">
          {{ formatKES(standing.accountCredit) }}
        </div>
        <div class="stat-trend positive">
          <span>{{ standing.accountCredit > 0 ? 'Carried forward towards next billing cycle' : 'No advance credit balance' }}</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Next Rent Due Date</div>
        <div class="stat-value mono" style="font-size: 1.35rem;">
          {{ standing.nextDueDate ? formatHumanDate(standing.nextDueDate) : '5th of month' }}
        </div>
        <div class="stat-trend neutral">
          <span>Projected by automated billing cycle</span>
        </div>
      </article>
    </section>

    <!-- Resident Information & Tenancy Grid -->
    <div class="details-grid">
      <!-- Contact & Personal Details -->
      <section class="card-panel">
        <div class="panel-section-title">
          <Users :size="16" />
          <h2>Contact & Verification</h2>
        </div>

        <div class="spec-grid">
          <div class="spec-item">
            <span class="spec-label">Phone Number</span>
            <strong class="spec-value mono">{{ tenant.phone }}</strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Email Address</span>
            <strong class="spec-value">{{ tenant.email }}</strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">National ID / Passport</span>
            <strong class="spec-value mono">{{ tenant.nationalId || 'Verified' }}</strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Emergency Contact</span>
            <strong class="spec-value">{{ tenant.emergencyContact || 'On file' }}</strong>
          </div>
        </div>
      </section>

      <!-- Assigned Unit & Lease Details -->
      <section class="card-panel">
        <div class="panel-section-title">
          <Building2 :size="16" />
          <h2>Current Tenancy</h2>
        </div>

        <div v-if="currentUnit" class="spec-grid">
          <div class="spec-item">
            <span class="spec-label">Assigned Unit</span>
            <strong class="spec-value">
              <router-link :to="`/units/${currentUnit.id}`" class="text-link">
                Unit {{ currentUnit.unitNumber }} ({{ currentUnit.type }})
              </router-link>
            </strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Monthly Rent</span>
            <strong class="spec-value text-positive">
              {{ formatKES(activeLease?.monthlyRent || getUnitMonthlyRent(currentUnit)) }}/mo
            </strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Agreement Reference</span>
            <strong class="spec-value mono">
              <router-link v-if="activeLease" :to="`/leases/${activeLease.id}`" class="text-link">
                {{ activeLease.leaseNumber }}
              </router-link>
              <span v-else>Active</span>
            </strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Lease Period</span>
            <strong class="spec-value">
              {{ activeLease ? `${formatHumanDate(activeLease.startDate)} → ${formatHumanDate(activeLease.endDate)}` : 'N/A' }}
            </strong>
          </div>
        </div>
        <div v-else style="padding: 20px 0; color: #64748b;">
          No active unit currently assigned.
        </div>
      </section>
    </div>

    <!-- Active Lease Agreement & Ledger Link Banner -->
    <div
      v-if="activeLease"
      class="panel"
      style="margin-top: 20px; padding: 16px 20px; background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap;"
    >
      <div>
        <strong style="color: #0f172a; font-size: 0.92rem; display: block;">Lease Agreement & Financial Ledger</strong>
        <p style="font-size: 0.82rem; color: #64748b; margin: 3px 0 0;">
          All verified payments, receipts, and contractual terms are cataloged under Lease <strong>{{ activeLease.leaseNumber }}</strong> (Unit {{ activeLease.unitNumber }}).
        </p>
      </div>
      <router-link :to="`/leases/${activeLease.id}`" class="primary-button" style="padding: 6px 14px; font-size: 0.82rem;">
        <span>View Lease & Payments</span>
      </router-link>
    </div>

    <!-- Official Printable Statement Side Sheet -->
    <TenantStatementSheet
      :open="showStatementSheet"
      :tenant="tenant"
      @close="showStatementSheet = false"
    />
  </div>

  <div v-else class="page-body" style="padding: 48px 16px; text-align: center;">
    <h2 style="font-size: 1.15rem; font-weight: 700; color: #172033; margin-bottom: 8px;">Resident Record Not Found</h2>
    <p style="color: #64748b; font-size: 0.88rem; margin: 0 0 18px 0;">This resident record is not currently loaded or does not exist.</p>
    <router-link to="/tenants" class="secondary-button" style="display: inline-flex; margin: 0 auto; gap: 6px;">
      <ArrowLeft :size="15" /> Back to Residents Directory
    </router-link>
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

.text-danger {
  color: #dc2626 !important;
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

.form-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.modal-actions {
  display: flex;
  justify-content: flex-end;
  gap: 10px;
  margin-top: 20px;
}

@media (max-width: 800px) {
  .details-grid {
    grid-template-columns: 1fr;
  }
}
</style>
