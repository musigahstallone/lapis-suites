<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  Building2,
  Users,
  FileText,
  CreditCard,
  ArrowLeft,
  Calendar,
  CheckCircle2,
  AlertCircle,
  Plus,
  KeyRound,
  ShieldCheck,
  ExternalLink
} from 'lucide-vue-next'
import {
  store,
  formatKES,
  formatHumanDate,
  getUnitTypeConfig,
  getUnitFeatures,
  getUnitMonthlyRent,
  fetchUnits,
  fetchUnitTypes,
  fetchTenants,
  fetchLeases
} from '../data'

const route = useRoute()
const router = useRouter()

const unitId = computed(() => route.params.id as string)
const unit = computed(() => store.units.find(u => u.id === unitId.value || u.unitNumber?.toLowerCase() === unitId.value?.toLowerCase()))

onMounted(async () => {
  await Promise.all([fetchUnits(), fetchUnitTypes(), fetchTenants(), fetchLeases()])
})

const unitTypeConfig = computed(() => {
  if (!unit.value) return undefined
  return getUnitTypeConfig(unit.value.type)
})

const features = computed(() => {
  if (!unit.value) return []
  return getUnitFeatures(unit.value.type)
})

const monthlyRent = computed(() => {
  if (!unit.value) return 0
  return getUnitMonthlyRent(unit.value)
})

const activeLease = computed(() => {
  if (!unit.value) return null
  return (
    store.leases.find(
      l =>
        (l.unitId === unit.value?.id || l.unitNumber === unit.value?.unitNumber) &&
        (l.status === 'active' || l.status === 'pending_deposit')
    ) || null
  )
})

const currentTenant = computed(() => {
  if (!unit.value) return null
  if (unit.value.currentTenantId) {
    const byId = store.tenants.find(t => t.id === unit.value?.currentTenantId)
    if (byId) return byId
  }
  if (activeLease.value?.tenantId) {
    const byLease = store.tenants.find(t => t.id === activeLease.value?.tenantId)
    if (byLease) return byLease
  }
  return (
    store.tenants.find(
      t => t.currentUnitId === unit.value?.id || (t.currentUnitNumber && t.currentUnitNumber === unit.value?.unitNumber)
    ) || null
  )
})

// Unit is occupied if it has an active lease, an assigned tenant, or status === 'occupied'
const isUnitAssigned = computed(() => Boolean(activeLease.value || currentTenant.value || unit.value?.status === 'occupied'))
</script>

<template>
  <div v-if="unit" class="page-body">
    <!-- Top Breadcrumb & Actions -->
    <div class="breadcrumb-bar">
      <router-link to="/units" class="back-link">
        <ArrowLeft :size="16" />
        <span>Back to Units</span>
      </router-link>
      <div class="status-indicator">
        <span :class="['badge', isUnitAssigned ? 'occupied' : unit.status]">● {{ isUnitAssigned ? 'occupied' : unit.status }}</span>
      </div>
    </div>

    <!-- Page Header -->
    <header class="page-intro" style="margin-bottom: 24px;">
      <div>
        <p class="eyebrow">{{ unitTypeConfig?.name || unit.type }}</p>
        <h1>Unit {{ unit.unitNumber }}</h1>
        <p>Managed apartment unit at Lapis Suites. Specifications inherited from Unit Type.</p>
      </div>

      <div class="intro-actions" style="display: flex; gap: 8px;">
        <router-link
          v-if="!isUnitAssigned"
          :to="`/units/${unit.id}/lease`"
          class="primary-button"
        >
          <KeyRound :size="15" />
          <span>Assign New Lease</span>
        </router-link>

        <template v-else>
          <router-link
            :to="`/units/${unit.id}/lease`"
            class="primary-button"
          >
            <FileText :size="15" />
            <span>Lease Changes</span>
          </router-link>

          <router-link
            v-if="currentTenant"
            :to="`/tenants/${currentTenant.id}`"
            class="secondary-button"
          >
            <Users :size="15" />
            <span>View Resident Profile</span>
          </router-link>
        </template>
      </div>
    </header>

    <!-- VACANT / UNASSIGNED UNIT: Minimal Clean Summary State -->
    <div v-if="!isUnitAssigned" class="details-grid">
      <section class="card-panel">
        <div class="panel-section-title">
          <Building2 :size="17" />
          <h2>Unit Specifications</h2>
        </div>

        <div class="spec-grid">
          <div class="spec-item">
            <span class="spec-label">Unit Number</span>
            <strong class="spec-value mono">Unit {{ unit.unitNumber }}</strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Unit Type</span>
            <strong class="spec-value">{{ unitTypeConfig?.name || unit.type }}</strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Standard Base Rent</span>
            <strong class="spec-value text-positive">{{ formatKES(monthlyRent) }}/mo</strong>
          </div>
          <div class="spec-item">
            <span class="spec-label">Security Deposit Rule</span>
            <strong class="spec-value">{{ unitTypeConfig?.depositMultiplier || 1.0 }}× Monthly Rent</strong>
          </div>
        </div>

        <div class="inherited-features-block">
          <h3>Inherited Features &amp; Amenities</h3>
          <p class="section-desc">Centrally managed on the {{ unitTypeConfig?.name }} catalog configuration.</p>
          <ul class="feature-tag-list">
            <li v-for="f in features" :key="f" class="feature-tag">
              <CheckCircle2 :size="13" />
              <span>{{ f }}</span>
            </li>
          </ul>
        </div>
      </section>

      <!-- Vacant Callout Card -->
      <section class="card-panel vacant-prompt-card">
        <div class="vacant-icon-wrap">
          <KeyRound :size="28" />
        </div>
        <h2>Ready for Tenancy</h2>
        <p>This unit is clean, inspected, and ready to be assigned to a new resident.</p>
        <router-link :to="`/units/${unit.id}/lease`" class="primary-button" style="margin-top: 16px;">
          <Plus :size="15" />
          <span>Assign New Lease</span>
        </router-link>
      </section>
    </div>

    <!-- OCCUPIED UNIT WITH ASSIGNED TENANT: Full Tenant, Lease, and Ledger Details -->
    <div v-else class="details-layout">
      <!-- Top Overview Row: Tenant & Active Lease -->
      <div class="occupancy-overview-grid">
        <!-- Resident Card -->
        <article class="stat-card">
          <div class="card-top-header">
            <span class="stat-label">Active Resident</span>
            <span class="badge active">Occupied</span>
          </div>

          <div v-if="currentTenant" class="resident-profile-snippet">
            <div class="resident-avatar">{{ currentTenant.avatarInitials }}</div>
            <div class="resident-names">
              <strong>{{ currentTenant.name }}</strong>
              <small>{{ currentTenant.phone }} · {{ currentTenant.email }}</small>
            </div>
          </div>

          <div v-if="currentTenant" class="ledger-snippet-bar">
            <div>
              <span class="sub-label">Ledger Balance</span>
              <strong :class="currentTenant.balance > 0 ? 'text-danger' : 'text-positive'">
                {{ currentTenant.balance > 0 ? `${formatKES(currentTenant.balance)} Arrears` : 'Settled' }}
              </strong>
            </div>
            <div>
              <span class="sub-label">Next Due Date</span>
              <strong class="mono">{{ currentTenant.nextPaymentDueDate ? formatHumanDate(currentTenant.nextPaymentDueDate) : '5th of month' }}</strong>
            </div>
          </div>

          <router-link
            v-if="currentTenant"
            :to="`/tenants/${currentTenant.id}`"
            class="text-link-btn"
          >
            <span>Full Resident Details</span>
            <ExternalLink :size="13" />
          </router-link>
        </article>

        <!-- Active Lease Card -->
        <article class="stat-card">
          <div class="card-top-header">
            <span class="stat-label">Lease Agreement</span>
            <span class="badge active">{{ activeLease?.leaseNumber || 'Active' }}</span>
          </div>

          <div v-if="activeLease" class="lease-snippet-content">
            <div class="spec-grid" style="grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 8px;">
              <div>
                <span class="sub-label">Term Duration</span>
                <strong>{{ formatHumanDate(activeLease.startDate) }} → {{ formatHumanDate(activeLease.endDate) }}</strong>
              </div>
              <div>
                <span class="sub-label">Agreed Rent</span>
                <strong class="text-positive">{{ formatKES(activeLease.monthlyRent) }}/mo</strong>
              </div>
              <div>
                <span class="sub-label">Deposit Held</span>
                <strong>{{ formatKES(activeLease.depositAmount) }}</strong>
              </div>
              <div>
                <span class="sub-label">Next Rent Due</span>
                <strong class="mono">{{ activeLease.nextPaymentDueDate ? formatHumanDate(activeLease.nextPaymentDueDate) : '5th of month' }}</strong>
              </div>
            </div>
          </div>

          <div style="display: flex; gap: 14px; margin-top: 10px;">
            <router-link
              v-if="activeLease"
              :to="`/leases/${activeLease.id}`"
              class="text-link-btn"
            >
              <span>Full Lease Agreement</span>
              <ExternalLink :size="13" />
            </router-link>
            <router-link
              :to="`/units/${unit.id}/lease`"
              class="text-link-btn"
            >
              <span>Manage Lease Changes</span>
              <ExternalLink :size="13" />
            </router-link>
          </div>
        </article>
      </div>

      <!-- Unit Type Features -->
      <section class="card-panel" style="margin-top: 20px;">
        <div class="panel-section-title">
          <Building2 :size="16" />
          <h2>Unit Specifications &amp; Amenities</h2>
        </div>
        <p class="section-desc">Inherited directly from the {{ unitTypeConfig?.name }} configuration.</p>
        <ul class="feature-tag-list">
          <li v-for="f in features" :key="f" class="feature-tag">
            <CheckCircle2 :size="13" />
            <span>{{ f }}</span>
          </li>
        </ul>
      </section>
    </div>
  </div>

  <div v-else class="page-body">
    <div style="padding: 40px; text-align: center;">
      <p>Unit not found.</p>
      <router-link to="/units" class="primary-button" style="display: inline-flex; margin-top: 14px;">
        Back to Units
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
  transition: color 0.12s ease;
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
  grid-template-columns: 1.6fr 1fr;
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
  font-size: 0.96rem;
  color: #0f172a;
}

.inherited-features-block {
  margin-top: 24px;
  padding-top: 18px;
  border-top: 1px solid #f1f5f9;
}

.inherited-features-block h3 {
  font-size: 0.92rem;
  font-weight: 700;
  margin: 0 0 4px;
  color: #0f172a;
}

.section-desc {
  font-size: 0.8rem;
  color: #64748b;
  margin: 0 0 12px;
}

.feature-tag-list {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  list-style: none;
  padding: 0;
  margin: 0;
}

.feature-tag {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 5px 10px;
  border-radius: 6px;
  background: #f8fafc;
  border: 1px solid #e2e8f0;
  font-size: 0.82rem;
  color: #334155;
}

.feature-tag svg {
  color: #059669;
}

.vacant-prompt-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 32px 24px;
  background: #fafafa;
}

.vacant-icon-wrap {
  width: 54px;
  height: 54px;
  border-radius: 50%;
  background: #eff6ff;
  color: #2563eb;
  display: grid;
  place-items: center;
  margin-bottom: 14px;
}

.vacant-prompt-card h2 {
  font-size: 1.1rem;
  font-weight: 700;
  margin: 0 0 6px;
}

.vacant-prompt-card p {
  font-size: 0.84rem;
  color: #64748b;
  max-width: 260px;
  margin: 0;
}

/* Occupied Layout */
.occupancy-overview-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}

.card-top-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;
}

.resident-profile-snippet {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 14px;
}

.resident-avatar {
  width: 40px;
  height: 40px;
  border-radius: 8px;
  background: #2563eb;
  color: #ffffff;
  display: grid;
  place-items: center;
  font-weight: 700;
  font-size: 0.92rem;
  flex: none;
}

.resident-names strong {
  display: block;
  font-size: 0.98rem;
  color: #0f172a;
}

.resident-names small {
  font-size: 0.78rem;
  color: #64748b;
}

.ledger-snippet-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 12px;
  background: #f8fafc;
  border-radius: 6px;
  border: 1px solid #f1f5f9;
  margin-bottom: 14px;
}

.sub-label {
  display: block;
  font-size: 0.7rem;
  color: #64748b;
  text-transform: uppercase;
  letter-spacing: 0.03em;
  margin-bottom: 2px;
}

.text-danger {
  color: #dc2626;
}

.text-positive {
  color: #059669;
}

.text-link-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 0.82rem;
  font-weight: 600;
  color: #2563eb;
  text-decoration: none;
  margin-top: 4px;
}

.text-link-btn:hover {
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
  .details-grid,
  .occupancy-overview-grid {
    grid-template-columns: 1fr;
  }
}
</style>
