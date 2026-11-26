<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { FileText, Plus, ShieldCheck } from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import SearchableSelect from './SearchableSelect.vue'
import { store, createLease, formatKES, getUnitMonthlyRent } from '../data'

const props = defineProps<{
  open: boolean
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'created'): void
}>()

const selectedTenantId = ref(store.tenants[0]?.id || '')
const selectedUnitId = ref('')
const startDate = ref(new Date().toISOString().split('T')[0])
const endDate = ref('')
const terms = ref('Standard 12-month residential lease agreement.')

// Financial Requirement Fields
const isOverrideEnabled = ref(false)
const manualMonthlyRent = ref<number | ''>('')
const manualDeposit = ref<number | ''>('')
const manualFirstMonth = ref<number | ''>('')
const error = ref('')

// Vacant units
const availableUnits = computed(() => {
  return store.units.filter(u => u.status === 'vacant')
})

// Auto-select first vacant unit
watch(
  availableUnits,
  (units) => {
    if (units.length > 0 && (!selectedUnitId.value || !units.some(u => u.id === selectedUnitId.value))) {
      selectedUnitId.value = units[0].id
    }
  },
  { immediate: true }
)

// Auto-calculate end date (1 year ahead)
watch(
  startDate,
  (val) => {
    if (val) {
      const d = new Date(val)
      d.setFullYear(d.getFullYear() + 1)
      endDate.value = d.toISOString().split('T')[0]
    }
  },
  { immediate: true }
)

const selectedUnit = computed(() => {
  return store.units.find(u => u.id === selectedUnitId.value)
})

// Default financial requirements:
// Monthly Rent tied to unit
// First Month Rent = unit.monthlyRent
// Security Deposit = 1.0 month rent (equivalent to one month's rent tied to unit type)
const defaultMonthlyRent = computed(() => selectedUnit.value ? getUnitMonthlyRent(selectedUnit.value) : 0)
const defaultFirstMonthRent = computed(() => defaultMonthlyRent.value)
const defaultDeposit = computed(() => defaultMonthlyRent.value)

const effectiveMonthlyRent = computed(() => {
  if (isOverrideEnabled.value && manualMonthlyRent.value !== '') {
    return Number(manualMonthlyRent.value)
  }
  return defaultMonthlyRent.value
})

const effectiveFirstMonthRent = computed(() => {
  if (isOverrideEnabled.value && manualFirstMonth.value !== '') {
    return Number(manualFirstMonth.value)
  }
  return defaultFirstMonthRent.value
})

const effectiveDeposit = computed(() => {
  if (isOverrideEnabled.value && manualDeposit.value !== '') {
    return Number(manualDeposit.value)
  }
  return defaultDeposit.value
})

const totalMoveInRequired = computed(() => {
  return effectiveFirstMonthRent.value + effectiveDeposit.value
})

// Options for SearchableSelect
const tenantSelectOptions = computed(() => {
  return store.tenants.map(t => {
    const activeL = store.leases.find(l => l.tenantId === t.id && (l.status === 'active' || l.status === 'pending_deposit'))
    const unitNum = t.currentUnitNumber || activeL?.unitNumber || 'Unassigned'
    return {
      value: t.id,
      label: t.name,
      sublabel: `${t.phone} · Unit ${unitNum}`
    }
  })
})

const unitSelectOptions = computed(() => {
  return availableUnits.value.map(u => ({
    value: u.id,
    label: `Unit ${u.unitNumber} (${u.type})`,
    sublabel: `${formatKES(getUnitMonthlyRent(u))}/mo`
  }))
})

// Synchronize manual fields when override is enabled
watch(isOverrideEnabled, (val) => {
  if (val) {
    manualMonthlyRent.value = defaultMonthlyRent.value
    manualFirstMonth.value = defaultFirstMonthRent.value
    manualDeposit.value = defaultDeposit.value
  }
})

async function handleCreate() {
  error.value = ''
  if (!selectedTenantId.value) {
    error.value = 'Please select a tenant.'
    return
  }
  if (!selectedUnitId.value) {
    error.value = 'Please select a vacant unit.'
    return
  }
  if (!startDate.value || !endDate.value) {
    error.value = 'Please provide valid start and end dates.'
    return
  }

  try {
    await createLease({
      tenantId: selectedTenantId.value,
      unitId: selectedUnitId.value,
      startDate: startDate.value,
      endDate: endDate.value,
      monthlyRent: effectiveMonthlyRent.value,
      depositAmount: effectiveDeposit.value,
      firstMonthRent: effectiveFirstMonthRent.value,
      terms: terms.value
    })

    emit('created')
    emit('close')
  } catch (e: any) {
    error.value = e?.message || 'Failed to create lease.'
  }
}
</script>

<template>
  <SideSheet
    :open="open"
    title="Create Lease Agreement"
    subtitle="Bind tenant to a vacant unit with automated billing engine setup."
    @close="emit('close')"
  >
    <form @submit.prevent="handleCreate">
      <div v-if="error" style="padding: 10px 12px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.82rem; margin-bottom: 14px;">
        {{ error }}
      </div>

      <div class="form-field">
        <label>Resident / Tenant *</label>
        <SearchableSelect
          v-model="selectedTenantId"
          :options="tenantSelectOptions"
          placeholder="Select resident..."
          search-placeholder="Search resident..."
        />
      </div>

      <div class="form-field">
        <label>Vacant Unit *</label>
        <SearchableSelect
          v-model="selectedUnitId"
          :options="unitSelectOptions"
          placeholder="Select vacant unit..."
          search-placeholder="Search vacant units..."
        />
      </div>

      <div class="form-row">
        <div class="form-field">
          <label>Lease Start Date</label>
          <input v-model="startDate" type="date" required />
        </div>
        <div class="form-field">
          <label>Lease End Date</label>
          <input v-model="endDate" type="date" required />
        </div>
      </div>

      <!-- Financial Move-In Requirements Box -->
      <div style="background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 14px; margin-bottom: 16px;">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px;">
          <div>
            <strong style="font-size: 0.88rem; color: #172033; display: block;">Initial Move-In Requirements</strong>
            <small style="color: #64748b; font-size: 0.76rem;">Default: 1st month rent + 1 month security deposit</small>
          </div>

          <!-- Override Toggle -->
          <label style="display: flex; align-items: center; gap: 6px; cursor: pointer; font-size: 0.78rem; font-weight: 600; color: #2563eb; margin: 0;">
            <input v-model="isOverrideEnabled" type="checkbox" style="width: auto; margin: 0;" />
            <span>Override Defaults</span>
          </label>
        </div>

        <div v-if="!isOverrideEnabled">
          <div style="display: flex; justify-content: space-between; font-size: 0.82rem; padding: 4px 0;">
            <span style="color: #64748b;">First Month's Rent:</span>
            <strong>{{ formatKES(defaultFirstMonthRent) }}</strong>
          </div>
          <div style="display: flex; justify-content: space-between; font-size: 0.82rem; padding: 4px 0;">
            <span style="color: #64748b;">Security Deposit (1.0x):</span>
            <strong>{{ formatKES(defaultDeposit) }}</strong>
          </div>
          <div style="display: flex; justify-content: space-between; font-size: 0.92rem; padding-top: 8px; margin-top: 6px; border-top: 1px solid #e2e8f0;">
            <span style="font-weight: 600; color: #172033;">Total Move-In Due:</span>
            <strong style="color: #059669;">{{ formatKES(totalMoveInRequired) }}</strong>
          </div>
        </div>

        <!-- Overridden Manual Fields -->
        <div v-else style="display: flex; flex-direction: column; gap: 10px; margin-top: 6px;">
          <div class="form-row">
            <div class="form-field" style="margin-bottom: 0;">
              <label>Monthly Rent (KES)</label>
              <input v-model.number="manualMonthlyRent" type="number" min="1000" />
            </div>
            <div class="form-field" style="margin-bottom: 0;">
              <label>First Month Rent (KES)</label>
              <input v-model.number="manualFirstMonth" type="number" min="0" />
            </div>
          </div>
          <div class="form-field" style="margin-bottom: 0;">
            <label>Security Deposit (KES)</label>
            <input v-model.number="manualDeposit" type="number" min="0" />
          </div>
          <div style="display: flex; justify-content: space-between; font-size: 0.92rem; padding-top: 8px; border-top: 1px solid #e2e8f0;">
            <span style="font-weight: 600; color: #172033;">Total Move-In (Overridden):</span>
            <strong style="color: #2563eb;">{{ formatKES(totalMoveInRequired) }}</strong>
          </div>
        </div>
      </div>

      <div class="form-field">
        <label>Terms & Clauses</label>
        <textarea v-model="terms" rows="2"></textarea>
      </div>

      <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 24px; padding-top: 16px; border-top: 1px solid #eef2f6;">
        <button type="button" class="secondary-button" @click="emit('close')">
          Cancel
        </button>
        <button type="submit" class="primary-button" :disabled="availableUnits.length === 0">
          <Plus :size="15" /> Create Lease
        </button>
      </div>
    </form>
  </SideSheet>
</template>
