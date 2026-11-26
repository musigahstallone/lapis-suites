<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowLeft,
  ArrowRightLeft,
  Sliders,
  KeyRound,
  Trash2,
  AlertCircle,
  CheckCircle2,
  Building2,
  FileText
} from 'lucide-vue-next'
import {
  store,
  formatKES,
  formatHumanDate,
  getUnitMonthlyRent,
  executeUnitTransfer,
  createLease,
  terminateLease,
  fetchTenants,
  fetchUnits,
  fetchLeases
} from '../data'
import SearchableSelect from '../components/SearchableSelect.vue'

const route = useRoute()
const router = useRouter()

const tenantId = computed(() => String(route.params.id || ''))
const tenant = computed(() =>
  store.tenants.find(
    t => t.id === tenantId.value || t.email?.toLowerCase() === tenantId.value.toLowerCase()
  )
)

const activeLease = computed(() => {
  if (!tenant.value) return null
  if (tenant.value.currentLeaseId) {
    const byId = store.leases.find(l => l.id === tenant.value?.currentLeaseId)
    if (byId && (byId.status === 'active' || byId.status === 'pending_deposit')) return byId
  }
  return (
    store.leases.find(
      l => l.tenantId === tenant.value?.id && (l.status === 'active' || l.status === 'pending_deposit')
    ) || null
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
  const num = tenant.value.currentUnitNumber || activeLease.value?.unitNumber
  if (num) return store.units.find(u => u.unitNumber === num) || null
  return null
})

const activeTab = ref<'transfer' | 'amend' | 'assign'>('transfer')

const vacantUnitOptions = computed(() => {
  return store.units
    .filter(u => u.status === 'vacant' && u.id !== currentUnit.value?.id)
    .map(u => ({
      value: u.id,
      label: `Unit ${u.unitNumber} (${u.type})`,
      sublabel: `${formatKES(getUnitMonthlyRent(u))}/mo`
    }))
})

// Transfer Form
const transferForm = ref({
  newUnitId: '',
  transferDate: new Date().toISOString().slice(0, 10),
  newRent: 0,
  depositRollOver: true,
  transferNotes: ''
})

// Amendment Form
const amendForm = ref({
  changeType: 'rent_adjustment' as 'rent_adjustment' | 'term_extension' | 'deposit_adjustment' | 'terms_amendment',
  effectiveDate: new Date().toISOString().slice(0, 10),
  newRent: 0,
  newEndDate: '',
  newDeposit: 0,
  reason: '',
  notes: ''
})

// Assign Lease Form (if tenant has no current unit)
const assignForm = ref({
  unitId: '',
  startDate: new Date().toISOString().slice(0, 10),
  endDate: '',
  monthlyRent: 0,
  depositAmount: 0,
  depositPaid: false,
  terms: ''
})

const amendments = ref<any[]>([])
const isSubmitting = ref(false)
const error = ref('')
const success = ref('')

const destinationUnit = computed(() => store.units.find(u => u.id === transferForm.value.newUnitId) || null)
const currentRent = computed(() => activeLease.value?.monthlyRent || (currentUnit.value ? getUnitMonthlyRent(currentUnit.value) : 0))
const rentDiff = computed(() => (transferForm.value.newRent || 0) - currentRent.value)

const tenantAmendments = computed(() => {
  if (!tenant.value) return []
  return amendments.value.filter(a => a.tenantId === tenant.value?.id)
})

watch(() => transferForm.value.newUnitId, (unitId) => {
  const target = store.units.find(u => u.id === unitId)
  if (target) {
    transferForm.value.newRent = getUnitMonthlyRent(target)
    if (!transferForm.value.transferNotes && tenant.value) {
      transferForm.value.transferNotes = `Internal unit transfer for ${tenant.value.name} to Unit ${target.unitNumber}.`
    }
  }
})

watch(() => assignForm.value.unitId, (unitId) => {
  const target = store.units.find(u => u.id === unitId)
  if (target) {
    const rent = getUnitMonthlyRent(target)
    assignForm.value.monthlyRent = rent
    assignForm.value.depositAmount = rent
    assignForm.value.terms = `Standard 12-month residential tenancy agreement for Unit ${target.unitNumber}.`
  }
})

function syncState() {
  if (!currentUnit.value) {
    activeTab.value = 'assign'
  } else if (activeTab.value === 'assign') {
    activeTab.value = 'transfer'
  }
  const oneYearLater = new Date()
  oneYearLater.setFullYear(oneYearLater.getFullYear() + 1)
  if (!assignForm.value.endDate) assignForm.value.endDate = oneYearLater.toISOString().slice(0, 10)

  if (activeLease.value) {
    amendForm.value.newRent = activeLease.value.monthlyRent
    amendForm.value.newDeposit = activeLease.value.depositAmount
    amendForm.value.newEndDate = activeLease.value.endDate
  }
}

watch([tenant, currentUnit, activeLease], () => syncState(), { immediate: true })

async function loadAmendments() {
  try {
    const headers: Record<string, string> = {}
    if (store.session.token) headers['Authorization'] = `Bearer ${store.session.token}`
    const res = await fetch('/api/leases-amendments', { headers })
    if (res.ok) amendments.value = await res.json()
  } catch {}
}

onMounted(async () => {
  await Promise.all([fetchTenants(), fetchUnits(), fetchLeases(), loadAmendments()])
  syncState()
})

async function handleExecuteTransfer() {
  error.value = ''
  success.value = ''
  if (!tenant.value || !currentUnit.value) return
  if (!transferForm.value.newUnitId) {
    error.value = 'Please select a destination vacant unit.'
    return
  }

  isSubmitting.value = true
  try {
    await executeUnitTransfer({
      tenantId: tenant.value.id,
      currentUnitId: currentUnit.value.id,
      newUnitId: transferForm.value.newUnitId,
      transferDate: transferForm.value.transferDate,
      newRent: Number(transferForm.value.newRent),
      depositRollOver: transferForm.value.depositRollOver,
      transferFee: 0,
      transferNotes: transferForm.value.transferNotes || `Internal transfer to Unit ${destinationUnit.value?.unitNumber}`
    })
    await Promise.all([fetchTenants(), fetchUnits(), fetchLeases()])
    transferForm.value.newUnitId = ''
    success.value = `Unit transfer executed! Resident has been moved and notified via SMS.`
  } catch (err: any) {
    error.value = err.message || 'Failed to complete unit transfer.'
  } finally {
    isSubmitting.value = false
  }
}

async function handleSaveAmendment() {
  error.value = ''
  success.value = ''
  if (!activeLease.value) return
  if (!amendForm.value.reason.trim()) {
    error.value = 'Please enter a reason for this lease amendment.'
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
    if (!res.ok) throw new Error(data.error || 'Failed to save amendment.')
    await Promise.all([fetchLeases(), loadAmendments()])
    amendForm.value.reason = ''
    amendForm.value.notes = ''
    success.value = `Lease ${activeLease.value.leaseNumber} amended and resident notified via SMS.`
  } catch (err: any) {
    error.value = err.message || 'Failed to apply amendment.'
  } finally {
    isSubmitting.value = false
  }
}

async function handleAssignUnit() {
  error.value = ''
  success.value = ''
  if (!tenant.value) return
  if (!assignForm.value.unitId) {
    error.value = 'Please select a vacant unit to assign.'
    return
  }

  isSubmitting.value = true
  try {
    await createLease({
      tenantId: tenant.value.id,
      unitId: assignForm.value.unitId,
      startDate: assignForm.value.startDate,
      endDate: assignForm.value.endDate,
      monthlyRent: Number(assignForm.value.monthlyRent),
      depositAmount: Number(assignForm.value.depositAmount),
      depositPaid: Boolean(assignForm.value.depositPaid),
      terms: assignForm.value.terms
    })
    await Promise.all([fetchTenants(), fetchUnits(), fetchLeases()])
    success.value = `New lease assigned to ${tenant.value.name} and welcome SMS dispatched.`
  } catch (err: any) {
    error.value = err.message || 'Failed to assign lease.'
  } finally {
    isSubmitting.value = false
  }
}

async function handleTerminate() {
  if (!activeLease.value || !tenant.value) return
  if (!confirm(`Terminate Lease ${activeLease.value.leaseNumber} for ${tenant.value.name}?`)) return
  isSubmitting.value = true
  error.value = ''
  success.value = ''
  try {
    await terminateLease(activeLease.value.id)
    await Promise.all([fetchTenants(), fetchUnits(), fetchLeases()])
    success.value = 'Lease terminated and unit marked vacant.'
  } catch (err: any) {
    error.value = err.message || 'Failed to terminate lease.'
  } finally {
    isSubmitting.value = false
  }
}
</script>

<template>
  <div v-if="tenant" class="page-body">
    <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
      <router-link :to="`/tenants/${tenant.id}`" class="text-button" style="display: inline-flex; align-items: center; gap: 6px;">
        <ArrowLeft :size="15" />
        <span>Back to {{ tenant.name }}</span>
      </router-link>
      <span v-if="currentUnit" class="badge occupied">Unit {{ currentUnit.unitNumber }}</span>
      <span v-else class="badge pending">Unassigned</span>
    </div>

    <header class="page-intro" style="margin-bottom: 20px;">
      <div>
        <p class="eyebrow">RESIDENT LEASE CHANGES</p>
        <h1>{{ tenant.name }} — Lease Changes &amp; Transfers</h1>
        <p>Execute unit transfers, rent or term amendments, lease assignments, and terminations cleanly.</p>
      </div>
    </header>

    <div v-if="error" class="auth-alert error" style="max-width: 880px;">
      <AlertCircle :size="16" class="auth-alert-icon" />
      <span>{{ error }}</span>
    </div>
    <div v-if="success" class="auth-alert success" style="max-width: 880px;">
      <CheckCircle2 :size="16" class="auth-alert-icon" />
      <span>{{ success }}</span>
    </div>

    <!-- Action Mode Tabs -->
    <div style="display: flex; gap: 8px; margin-bottom: 20px; flex-wrap: wrap;">
      <button
        v-if="currentUnit"
        type="button"
        class="secondary-button"
        :style="activeTab === 'transfer' ? 'background: #0f172a; color: white; border-color: #0f172a;' : ''"
        @click="activeTab = 'transfer'; error = ''; success = ''"
      >
        <ArrowRightLeft :size="14" />
        <span>Unit Transfer</span>
      </button>

      <button
        v-if="activeLease"
        type="button"
        class="secondary-button"
        :style="activeTab === 'amend' ? 'background: #0f172a; color: white; border-color: #0f172a;' : ''"
        @click="activeTab = 'amend'; error = ''; success = ''"
      >
        <Sliders :size="14" />
        <span>Amend Lease</span>
      </button>

      <button
        v-if="!currentUnit"
        type="button"
        class="secondary-button"
        :style="activeTab === 'assign' ? 'background: #0f172a; color: white; border-color: #0f172a;' : ''"
        @click="activeTab = 'assign'; error = ''; success = ''"
      >
        <KeyRound :size="14" />
        <span>Assign Vacant Unit</span>
      </button>
    </div>

    <div style="display: grid; grid-template-columns: 1.3fr 0.7fr; gap: 22px; align-items: start;">
      <!-- LEFT PANEL: ACTIVE FORM -->
      <section class="panel" style="padding: 24px;">
        <!-- TAB 1: UNIT TRANSFER -->
        <form v-if="activeTab === 'transfer' && currentUnit" @submit.prevent="handleExecuteTransfer">
          <h2 style="font-size: 1.05rem; margin: 0 0 14px;">Transfer from Unit {{ currentUnit.unitNumber }} to Vacant Unit</h2>

          <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 16px;">
            <div style="padding: 12px; border: 1px solid #e2e8f0; border-radius: 8px; background: #f8fafc;">
              <small style="font-size: 0.72rem; color: #64748b; font-weight: 600; text-transform: uppercase;">Current Unit</small>
              <strong style="display: block; font-size: 1rem; margin-top: 2px;">Unit {{ currentUnit.unitNumber }}</strong>
              <span style="font-size: 0.8rem; color: #64748b;">{{ formatKES(currentRent) }}/mo · {{ currentUnit.type }}</span>
            </div>
            <div style="padding: 12px; border: 1px solid #bfdbfe; border-radius: 8px; background: #eff6ff;">
              <small style="font-size: 0.72rem; color: #1d4ed8; font-weight: 600; text-transform: uppercase;">Destination Unit</small>
              <strong style="display: block; font-size: 1rem; margin-top: 2px; color: #1e3a8a;">
                {{ destinationUnit ? `Unit ${destinationUnit.unitNumber}` : 'Select below' }}
              </strong>
              <span style="font-size: 0.8rem; color: #1e40af;">
                {{ destinationUnit ? `${formatKES(transferForm.newRent)}/mo (${rentDiff >= 0 ? '+' : ''}${formatKES(rentDiff)})` : 'Choose vacant destination' }}
              </span>
            </div>
          </div>

          <div class="form-field" style="margin-bottom: 14px;">
            <label>Destination Vacant Unit *</label>
            <SearchableSelect
              v-model="transferForm.newUnitId"
              :options="vacantUnitOptions"
              placeholder="Select destination vacant unit..."
              search-placeholder="Search vacant unit number or type..."
            />
          </div>

          <div class="form-row">
            <div class="form-field">
              <label>Transfer Effective Date *</label>
              <input v-model="transferForm.transferDate" type="date" required />
            </div>
            <div class="form-field">
              <label>New Monthly Rent (KES) *</label>
              <input v-model.number="transferForm.newRent" type="number" min="1" required />
            </div>
          </div>

          <div style="padding: 12px 14px; border: 1px solid #e2e8f0; border-radius: 7px; background: #fafbfc; margin-bottom: 14px;">
            <label style="display: flex; align-items: center; gap: 8px; margin: 0; cursor: pointer; font-size: 0.84rem;">
              <input v-model="transferForm.depositRollOver" type="checkbox" style="width: auto; margin: 0;" />
              <span>Roll over existing security deposit to the new unit lease</span>
            </label>
          </div>

          <div class="form-field">
            <label>Transfer Notes</label>
            <textarea v-model="transferForm.transferNotes" rows="2" placeholder="Reason for transfer..."></textarea>
          </div>

          <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 18px; padding-top: 14px; border-top: 1px solid #eef2f6;">
            <router-link :to="`/tenants/${tenant.id}`" class="secondary-button">Cancel</router-link>
            <button type="submit" class="primary-button" :disabled="isSubmitting || !transferForm.newUnitId">
              <ArrowRightLeft :size="15" />
              <span>{{ isSubmitting ? 'Executing Transfer...' : 'Confirm & Execute Transfer' }}</span>
            </button>
          </div>
        </form>

        <!-- TAB 2: AMEND ACTIVE LEASE -->
        <form v-else-if="activeTab === 'amend' && activeLease" @submit.prevent="handleSaveAmendment">
          <h2 style="font-size: 1.05rem; margin: 0 0 14px;">Amend Lease {{ activeLease.leaseNumber }} (Unit {{ activeLease.unitNumber }})</h2>

          <div class="form-row">
            <div class="form-field">
              <label>Change Type *</label>
              <select v-model="amendForm.changeType">
                <option value="rent_adjustment">Rent Adjustment</option>
                <option value="term_extension">Term Extension</option>
                <option value="deposit_adjustment">Deposit Adjustment</option>
                <option value="terms_amendment">Terms Amendment</option>
              </select>
            </div>
            <div class="form-field">
              <label>Effective Date *</label>
              <input v-model="amendForm.effectiveDate" type="date" required />
            </div>
          </div>

          <div class="form-row">
            <div class="form-field">
              <label>New Monthly Rent (KES)</label>
              <input v-model.number="amendForm.newRent" type="number" min="1" />
            </div>
            <div class="form-field">
              <label>New Lease End Date</label>
              <input v-model="amendForm.newEndDate" type="date" />
            </div>
          </div>

          <div class="form-field">
            <label>New Deposit Amount (KES)</label>
            <input v-model.number="amendForm.newDeposit" type="number" min="0" />
          </div>

          <div class="form-field">
            <label>Reason for Amendment *</label>
            <input v-model="amendForm.reason" required placeholder="e.g. Lease renewal or agreed rent change" />
          </div>

          <div class="form-field">
            <label>Additional Notes</label>
            <textarea v-model="amendForm.notes" rows="2"></textarea>
          </div>

          <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 18px; padding-top: 14px; border-top: 1px solid #eef2f6;">
            <button type="submit" class="primary-button" :disabled="isSubmitting">
              <FileText :size="15" />
              <span>{{ isSubmitting ? 'Applying Amendment...' : 'Save Lease Amendment' }}</span>
            </button>
          </div>
        </form>

        <!-- TAB 3: ASSIGN VACANT UNIT -->
        <form v-else @submit.prevent="handleAssignUnit">
          <h2 style="font-size: 1.05rem; margin: 0 0 14px;">Assign Vacant Unit to {{ tenant.name }}</h2>

          <div class="form-field" style="margin-bottom: 14px;">
            <label>Select Vacant Unit *</label>
            <SearchableSelect
              v-model="assignForm.unitId"
              :options="vacantUnitOptions"
              placeholder="Select available vacant unit..."
              search-placeholder="Search vacant unit..."
            />
          </div>

          <div class="form-row">
            <div class="form-field">
              <label>Start Date *</label>
              <input v-model="assignForm.startDate" type="date" required />
            </div>
            <div class="form-field">
              <label>End Date *</label>
              <input v-model="assignForm.endDate" type="date" required />
            </div>
          </div>

          <div class="form-row">
            <div class="form-field">
              <label>Monthly Rent (KES) *</label>
              <input v-model.number="assignForm.monthlyRent" type="number" min="1" required />
            </div>
            <div class="form-field">
              <label>Security Deposit (KES) *</label>
              <input v-model.number="assignForm.depositAmount" type="number" min="0" required />
            </div>
          </div>

          <div class="form-field">
            <label>Terms</label>
            <textarea v-model="assignForm.terms" rows="2"></textarea>
          </div>

          <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 18px; padding-top: 14px; border-top: 1px solid #eef2f6;">
            <button type="submit" class="primary-button" :disabled="isSubmitting || !assignForm.unitId">
              <KeyRound :size="15" />
              <span>{{ isSubmitting ? 'Assigning...' : 'Assign Lease' }}</span>
            </button>
          </div>
        </form>
      </section>

      <!-- RIGHT PANEL: TENANT SUMMARY + HISTORY -->
      <div style="display: flex; flex-direction: column; gap: 18px;">
        <section class="panel" style="padding: 20px;">
          <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 10px;">
            <Building2 :size="16" style="color: #2563eb;" />
            <h3 style="font-size: 0.96rem; margin: 0;">Current Tenancy</h3>
          </div>
          <div style="font-size: 0.84rem; display: grid; gap: 6px; color: #334155;">
            <div><strong>{{ tenant.name }}</strong></div>
            <div class="mono" style="font-size: 0.78rem; color: #64748b;">{{ tenant.phone }}</div>
            <div v-if="activeLease" style="padding-top: 8px; border-top: 1px solid #eef2f6; display: grid; gap: 4px;">
              <div>Unit: <strong>Unit {{ activeLease.unitNumber }}</strong></div>
              <div>Lease: <strong class="mono">{{ activeLease.leaseNumber }}</strong></div>
              <div>Rent: <strong style="color: #059669;">{{ formatKES(activeLease.monthlyRent) }}/mo</strong></div>
              <div>Ends: <strong>{{ formatHumanDate(activeLease.endDate) }}</strong></div>
            </div>
            <div v-else style="color: #64748b;">No active lease assigned.</div>
          </div>

          <button
            v-if="activeLease"
            type="button"
            class="secondary-button"
            style="width: 100%; margin-top: 14px; justify-content: center; color: #b91c1c; border-color: #fecaca;"
            :disabled="isSubmitting"
            @click="handleTerminate"
          >
            <Trash2 :size="14" />
            <span>Terminate Active Lease</span>
          </button>
        </section>

        <section class="panel" style="padding: 20px;">
          <h3 style="font-size: 0.96rem; margin: 0 0 10px;">Lease Change History ({{ tenantAmendments.length }})</h3>
          <div v-if="tenantAmendments.length === 0" style="font-size: 0.82rem; color: #64748b;">
            No amendments recorded for this resident yet.
          </div>
          <div v-else style="display: grid; gap: 10px;">
            <div
              v-for="a in tenantAmendments"
              :key="a.id"
              style="padding: 10px 12px; border: 1px solid #e2e8f0; border-radius: 6px; background: #fafbfc; font-size: 0.8rem;"
            >
              <div style="display: flex; justify-content: space-between; font-weight: 700;">
                <span>{{ a.reason }}</span>
                <span class="mono" style="font-size: 0.72rem; color: #64748b;">{{ a.effectiveDate }}</span>
              </div>
              <div style="color: #64748b; margin-top: 3px;">
                Unit {{ a.unitNumber }} · {{ formatKES(a.previousRent) }} → <strong>{{ formatKES(a.newRent) }}</strong>
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>
  </div>

  <div v-else class="page-body" style="padding: 40px; text-align: center;">
    <p>Resident not found.</p>
    <router-link to="/tenants" class="primary-button" style="display: inline-flex; margin-top: 12px;">Back to Tenants</router-link>
  </div>
</template>
