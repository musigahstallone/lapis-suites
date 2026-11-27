<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowLeft,
  KeyRound,
  Building2,
  Users,
  FileText,
  Download,
  AlertCircle,
  CheckCircle2,
  ArrowRightLeft,
  Sliders,
  Trash2
} from 'lucide-vue-next'
import {
  store,
  formatKES,
  formatHumanDate,
  getUnitTypeConfig,
  getUnitMonthlyRent,
  createLease,
  terminateLease,
  fetchUnits,
  fetchUnitTypes,
  fetchTenants,
  fetchLeases
} from '../data'
import SearchableSelect from '../components/SearchableSelect.vue'
import { downloadLeaseAgreementPdf } from '../utils/leaseAgreementGenerator'

const route = useRoute()
const router = useRouter()

const unitId = computed(() => String(route.params.id || ''))
const unit = computed(() =>
  store.units.find(
    u => u.id === unitId.value || u.unitNumber?.toLowerCase() === unitId.value.toLowerCase()
  )
)

const unitTypeConfig = computed(() => (unit.value ? getUnitTypeConfig(unit.value.type) : undefined))
const baseRent = computed(() => (unit.value ? getUnitMonthlyRent(unit.value) : 0))

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

const isOccupied = computed(() => Boolean(activeLease.value || currentTenant.value || unit.value?.status === 'occupied'))

// Assign New Lease Form (Vacant Unit)
const showAllTenants = ref(false)
const assignForm = ref({
  tenantId: '',
  startDate: new Date().toISOString().slice(0, 10),
  endDate: '',
  monthlyRent: 0,
  depositAmount: 0,
  depositPaid: false,
  terms: ''
})

// Amend Active Lease Form (Occupied Unit)
const amendForm = ref({
  changeType: 'rent_adjustment' as 'rent_adjustment' | 'term_extension' | 'deposit_adjustment' | 'terms_amendment',
  effectiveDate: new Date().toISOString().slice(0, 10),
  newRent: 0,
  newEndDate: '',
  newDeposit: 0,
  reason: '',
  notes: ''
})

const amendments = ref<any[]>([])
const isSubmitting = ref(false)
const error = ref('')
const success = ref('')

const tenantOptions = computed(() => {
  const list = showAllTenants.value
    ? store.tenants
    : store.tenants.filter(t => !t.currentUnitId && !t.currentUnitNumber)

  return list.map(t => ({
    value: t.id,
    label: t.name,
    sublabel: `${t.phone || 'No phone'} · ${t.email}${t.currentUnitNumber ? ` · Current: Unit ${t.currentUnitNumber}` : ' · Unassigned'}`
  }))
})

const unitAmendments = computed(() => {
  if (!unit.value) return []
  return amendments.value.filter(
    a => a.unitNumber === unit.value?.unitNumber || (activeLease.value && a.leaseId === activeLease.value.id)
  )
})

function syncForms() {
  if (!unit.value) return
  const rent = baseRent.value

  // End Date is intentionally left blank unless the landlord explicitly sets one
  if (!assignForm.value.monthlyRent) assignForm.value.monthlyRent = rent
  if (!assignForm.value.depositAmount) assignForm.value.depositAmount = rent
  if (!assignForm.value.terms) {
    assignForm.value.terms = `Residential tenancy agreement for Unit ${unit.value.unitNumber}. Landlord collects monthly rent and refundable security deposit only (water & electricity settled directly by resident).`
  }

  if (activeLease.value) {
    amendForm.value.newRent = activeLease.value.monthlyRent
    amendForm.value.newDeposit = activeLease.value.depositAmount
    amendForm.value.newEndDate = activeLease.value.endDate || ''
  }
}

watch([unit, activeLease], () => syncForms(), { immediate: true })

async function loadAmendments() {
  try {
    const headers: Record<string, string> = {}
    if (store.session.token) headers['Authorization'] = `Bearer ${store.session.token}`
    const res = await fetch('/api/leases-amendments', { headers })
    if (res.ok) amendments.value = await res.json()
  } catch {}
}

onMounted(async () => {
  await Promise.all([fetchUnits(), fetchUnitTypes(), fetchTenants(), fetchLeases(), loadAmendments()])
  syncForms()
})

async function handleAssignLease() {
  error.value = ''
  success.value = ''
  if (!unit.value) return
  if (!assignForm.value.tenantId) {
    error.value = 'Please select a tenant to assign to this unit.'
    return
  }
  if (!assignForm.value.startDate) {
    error.value = 'Please specify a valid lease start date.'
    return
  }

  isSubmitting.value = true
  try {
    await createLease({
      tenantId: assignForm.value.tenantId,
      unitId: unit.value.id,
      startDate: assignForm.value.startDate,
      endDate: assignForm.value.endDate || '',
      monthlyRent: Number(assignForm.value.monthlyRent),
      depositAmount: Number(assignForm.value.depositAmount),
      depositPaid: Boolean(assignForm.value.depositPaid),
      terms: assignForm.value.terms
    })
    await Promise.all([fetchUnits(), fetchTenants(), fetchLeases()])
    success.value = `Lease assigned successfully to Unit ${unit.value.unitNumber}!`
  } catch (err: any) {
    error.value = err.message || 'Failed to assign lease.'
  } finally {
    isSubmitting.value = false
  }
}

async function handleAmendLease() {
  error.value = ''
  success.value = ''
  if (!activeLease.value) return
  if (!amendForm.value.reason.trim()) {
    error.value = 'Please enter a reason for this lease change.'
    return
  }

  isSubmitting.value = true
  try {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' }
    if (store.session.token) headers['Authorization'] = `Bearer ${store.session.token}`
    const res = await fetch(`/api/leases/${activeLease.value.id}/amend`, {
      method: 'POST',
      headers,
      body: JSON.stringify(amendForm.value)
    })
    const data = await res.json()
    if (!res.ok) throw new Error(data.error || 'Failed to record lease amendment.')

    await Promise.all([fetchLeases(), loadAmendments()])
    amendForm.value.reason = ''
    amendForm.value.notes = ''
    success.value = `Lease ${activeLease.value.leaseNumber} updated and tenant notified via SMS.`
  } catch (err: any) {
    error.value = err.message || 'Failed to apply lease change.'
  } finally {
    isSubmitting.value = false
  }
}

async function handleTerminateLease() {
  if (!activeLease.value || !unit.value) return
  if (!confirm(`Terminate Lease ${activeLease.value.leaseNumber} and mark Unit ${unit.value.unitNumber} vacant?`)) {
    return
  }

  isSubmitting.value = true
  error.value = ''
  success.value = ''
  try {
    await terminateLease(activeLease.value.id)
    await Promise.all([fetchUnits(), fetchTenants(), fetchLeases()])
    success.value = `Lease terminated. Unit ${unit.value.unitNumber} is now vacant and ready for a new tenant.`
  } catch (err: any) {
    error.value = err.message || 'Failed to terminate lease.'
  } finally {
    isSubmitting.value = false
  }
}
</script>

<template>
  <div v-if="unit" class="page-body">
    <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
      <router-link :to="`/units/${unit.id}`" class="text-button" style="display: inline-flex; align-items: center; gap: 6px;">
        <ArrowLeft :size="15" />
        <span>Back to Unit {{ unit.unitNumber }}</span>
      </router-link>
      <span :class="['badge', isOccupied ? 'occupied' : 'vacant']">● {{ isOccupied ? 'occupied' : 'vacant' }}</span>
    </div>

    <header class="page-intro" style="margin-bottom: 22px;">
      <div>
        <p class="eyebrow">UNIT LEASE MANAGEMENT</p>
        <h1>Unit {{ unit.unitNumber }} — {{ isOccupied ? 'Lease Changes & Management' : 'Assign New Lease' }}</h1>
        <p>{{ unitTypeConfig?.name || unit.type }} · Base Rent {{ formatKES(baseRent) }}/mo</p>
      </div>

      <div v-if="currentTenant" class="intro-actions" style="display: flex; gap: 8px;">
        <router-link :to="`/tenants/${currentTenant.id}/lease-changes`" class="secondary-button">
          <ArrowRightLeft :size="15" />
          <span>Transfer Resident</span>
        </router-link>
        <router-link :to="`/tenants/${currentTenant.id}`" class="secondary-button">
          <Users :size="15" />
          <span>Resident Profile</span>
        </router-link>
      </div>
    </header>

    <div v-if="error" class="auth-alert error" style="max-width: 820px;">
      <AlertCircle :size="16" class="auth-alert-icon" />
      <span>{{ error }}</span>
    </div>

    <div v-if="success" class="auth-alert success" style="max-width: 820px;">
      <CheckCircle2 :size="16" class="auth-alert-icon" />
      <span>{{ success }}</span>
    </div>

    <!-- VACANT UNIT: ASSIGN NEW LEASE WITH TENANT SELECTOR -->
    <div v-if="!isOccupied" style="max-width: 780px;">
      <section class="panel" style="padding: 24px;">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; flex-wrap: wrap; gap: 10px;">
          <div style="display: flex; align-items: center; gap: 8px;">
            <KeyRound :size="18" style="color: #2563eb;" />
            <h2 style="font-size: 1.08rem; margin: 0;">Assign Resident to Unit {{ unit.unitNumber }}</h2>
          </div>

          <label style="display: inline-flex; align-items: center; gap: 6px; font-size: 0.8rem; color: #475569; cursor: pointer; margin: 0;">
            <input v-model="showAllTenants" type="checkbox" style="width: auto; margin: 0;" />
            <span>Include residents already assigned to another unit</span>
          </label>
        </div>

        <form @submit.prevent="handleAssignLease">
          <div class="form-field" style="margin-bottom: 16px;">
            <label>Select Resident / Tenant *</label>
            <SearchableSelect
              v-model="assignForm.tenantId"
              :options="tenantOptions"
              placeholder="Choose resident to assign to this unit..."
              search-placeholder="Search by name, phone, or email..."
            />
            <small v-if="tenantOptions.length === 0" style="color: #b45309; font-size: 0.78rem; display: block; margin-top: 5px;">
              No unassigned residents found. Add a new resident on the Tenants page or check "Include residents already assigned" above.
            </small>
          </div>

          <div class="form-row">
            <div class="form-field">
              <label>Lease Start Date *</label>
              <input v-model="assignForm.startDate" type="date" required />
            </div>
            <div class="form-field">
              <label>Lease End Date (Optional — leave blank if ongoing)</label>
              <input v-model="assignForm.endDate" type="date" />
            </div>
          </div>

          <div class="form-row">
            <div class="form-field">
              <label>Agreed Monthly Rent (KES) *</label>
              <input v-model.number="assignForm.monthlyRent" type="number" min="1" required />
            </div>
            <div class="form-field">
              <label>Security Deposit (KES) *</label>
              <input v-model.number="assignForm.depositAmount" type="number" min="0" required />
            </div>
          </div>

          <div style="padding: 12px 14px; border: 1px solid #e2e8f0; border-radius: 7px; background: #fafbfc; margin-bottom: 14px;">
            <label style="display: flex; align-items: center; gap: 8px; margin: 0; cursor: pointer; font-size: 0.84rem;">
              <input v-model="assignForm.depositPaid" type="checkbox" style="width: auto; margin: 0;" />
              <span>Security deposit has already been paid (activates lease immediately)</span>
            </label>
          </div>

          <div class="form-field">
            <label>Agreement Terms &amp; Notes</label>
            <textarea v-model="assignForm.terms" rows="3"></textarea>
          </div>

          <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 20px; padding-top: 16px; border-top: 1px solid #eef2f6;">
            <router-link :to="`/units/${unit.id}`" class="secondary-button">Cancel</router-link>
            <button type="submit" class="primary-button" :disabled="isSubmitting || !assignForm.tenantId">
              <KeyRound :size="15" />
              <span>{{ isSubmitting ? 'Assigning Lease...' : 'Confirm & Assign Lease' }}</span>
            </button>
          </div>
        </form>
      </section>
    </div>

    <!-- OCCUPIED UNIT: LEASE AMENDMENTS, TRANSFER LINK & TERMINATION -->
    <div v-else style="display: grid; grid-template-columns: 1.2fr 0.8fr; gap: 22px; align-items: start;">
      <!-- Left: Record Lease Amendment -->
      <section class="panel" style="padding: 24px;">
        <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 14px;">
          <Sliders :size="18" style="color: #2563eb;" />
          <h2 style="font-size: 1.05rem; margin: 0;">Amend Active Lease ({{ activeLease?.leaseNumber || 'Active' }})</h2>
        </div>

        <form v-if="activeLease" @submit.prevent="handleAmendLease">
          <div class="form-row">
            <div class="form-field">
              <label>Change Type *</label>
              <select v-model="amendForm.changeType">
                <option value="rent_adjustment">Monthly Rent Adjustment</option>
                <option value="term_extension">Lease Term Extension</option>
                <option value="deposit_adjustment">Security Deposit Adjustment</option>
                <option value="terms_amendment">General Terms Amendment</option>
              </select>
            </div>
            <div class="form-field">
              <label>Effective Date *</label>
              <input v-model="amendForm.effectiveDate" type="date" required />
            </div>
          </div>

          <div class="form-row">
            <div class="form-field">
              <label>Updated Monthly Rent (KES)</label>
              <input v-model.number="amendForm.newRent" type="number" min="1" />
            </div>
            <div class="form-field">
              <label>Updated End Date</label>
              <input v-model="amendForm.newEndDate" type="date" />
            </div>
          </div>

          <div class="form-field">
            <label>Updated Security Deposit (KES)</label>
            <input v-model.number="amendForm.newDeposit" type="number" min="0" />
          </div>

          <div class="form-field">
            <label>Reason for Lease Change *</label>
            <input v-model="amendForm.reason" required placeholder="e.g. Annual lease renewal or rent review" />
          </div>

          <div class="form-field">
            <label>Additional Notes</label>
            <textarea v-model="amendForm.notes" rows="2" placeholder="Optional details recorded on the lease agreement..."></textarea>
          </div>

          <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 18px; padding-top: 14px; border-top: 1px solid #eef2f6;">
            <button type="submit" class="primary-button" :disabled="isSubmitting">
              <FileText :size="15" />
              <span>{{ isSubmitting ? 'Saving Amendment...' : 'Apply Lease Amendment' }}</span>
            </button>
          </div>
        </form>
      </section>

      <!-- Right: Current Occupancy Summary & Danger Zone -->
      <div style="display: flex; flex-direction: column; gap: 18px;">
        <section class="panel" style="padding: 20px;">
          <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 12px;">
            <Building2 :size="17" style="color: #059669;" />
            <h3 style="font-size: 0.96rem; margin: 0;">Current Occupant</h3>
          </div>

          <div v-if="currentTenant" style="display: grid; gap: 8px; font-size: 0.85rem;">
            <div><strong>{{ currentTenant.name }}</strong></div>
            <div style="color: #64748b;">{{ currentTenant.email }} · <span class="mono">{{ currentTenant.phone }}</span></div>
            <div v-if="activeLease" style="padding-top: 8px; border-top: 1px solid #eef2f6; display: grid; gap: 4px;">
              <div>Agreement: <strong class="mono">{{ activeLease.leaseNumber }}</strong></div>
              <div>Rent: <strong style="color: #059669;">{{ formatKES(activeLease.monthlyRent) }}/mo</strong></div>
              <div>Period: <strong>{{ formatHumanDate(activeLease.startDate) }} → {{ formatHumanDate(activeLease.endDate) }}</strong></div>
            </div>
          </div>

          <div v-if="currentTenant" style="display: flex; flex-direction: column; gap: 8px; margin-top: 16px;">
            <button
              v-if="activeLease"
              type="button"
              class="primary-button"
              style="justify-content: center;"
              @click="downloadLeaseAgreementPdf(activeLease, currentTenant, unit)"
            >
              <Download :size="15" />
              <span>Download Tenancy Agreement PDF</span>
            </button>

            <router-link :to="`/tenants/${currentTenant.id}/lease-changes`" class="secondary-button" style="justify-content: center;">
              <ArrowRightLeft :size="15" />
              <span>Transfer Resident to Another Unit</span>
            </router-link>

            <button
              v-if="activeLease"
              type="button"
              class="secondary-button"
              style="color: #b91c1c; border-color: #fecaca; justify-content: center;"
              :disabled="isSubmitting"
              @click="handleTerminateLease"
            >
              <Trash2 :size="14" />
              <span>Terminate Lease &amp; Vacate Unit</span>
            </button>
          </div>
        </section>

        <!-- Unit Amendment History -->
        <section class="panel" style="padding: 20px;">
          <h3 style="font-size: 0.96rem; margin: 0 0 12px;">Amendment History ({{ unitAmendments.length }})</h3>
          <div v-if="unitAmendments.length === 0" style="font-size: 0.82rem; color: #64748b;">
            No amendments recorded for Unit {{ unit.unitNumber }} yet.
          </div>
          <div v-else style="display: grid; gap: 10px;">
            <div
              v-for="a in unitAmendments"
              :key="a.id"
              style="padding: 10px 12px; border: 1px solid #e2e8f0; border-radius: 6px; background: #fafbfc; font-size: 0.8rem;"
            >
              <div style="display: flex; justify-content: space-between; font-weight: 700; color: #172033;">
                <span>{{ a.reason }}</span>
                <span class="mono" style="font-size: 0.74rem; color: #64748b;">{{ a.effectiveDate }}</span>
              </div>
              <div style="color: #64748b; margin-top: 4px;">
                Rent: {{ formatKES(a.previousRent) }} → <strong>{{ formatKES(a.newRent) }}</strong>
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>
  </div>

  <div v-else class="page-body" style="padding: 40px; text-align: center;">
    <p>Unit not found.</p>
    <router-link to="/units" class="primary-button" style="display: inline-flex; margin-top: 12px;">Back to Units</router-link>
  </div>
</template>
