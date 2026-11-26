<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { ArrowRightLeft, ShieldCheck } from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import SearchableSelect from './SearchableSelect.vue'
import { store, executeUnitTransfer, formatKES, getUnitMonthlyRent } from '../data'

const props = defineProps<{
  open: boolean
  defaultTenantId?: string
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'transferred'): void
}>()

const selectedTenantId = ref(props.defaultTenantId || store.tenants[0]?.id || '')
const selectedNewUnitId = ref('')
const transferDate = ref(new Date().toISOString().slice(0, 10))
const depositRollOver = ref(true)
const transferNotes = ref('')
const isSubmitting = ref(false)
const error = ref('')

watch(
  () => props.defaultTenantId,
  (val) => {
    if (val) selectedTenantId.value = val
  }
)

const currentTenant = computed(() => {
  return store.tenants.find(t => t.id === selectedTenantId.value)
})

const currentUnit = computed(() => {
  if (!currentTenant.value) return null
  return store.units.find(u => u.id === currentTenant.value?.currentUnitId)
})

const currentLease = computed(() => {
  if (!currentTenant.value) return null
  return store.leases.find(l => l.tenantId === currentTenant.value?.id && l.status === 'active')
})

const availableUnits = computed(() => {
  return store.units.filter(u => u.status === 'vacant' && u.id !== currentTenant.value?.currentUnitId)
})

const destinationUnit = computed(() => {
  return store.units.find(u => u.id === selectedNewUnitId.value)
})

const currentRent = computed(() => currentUnit.value ? getUnitMonthlyRent(currentUnit.value) : 0)
const destinationRent = computed(() => destinationUnit.value ? getUnitMonthlyRent(destinationUnit.value) : 0)

const rentDiff = computed(() => {
  return destinationRent.value - currentRent.value
})

const tenantSelectOptions = computed(() => {
  return store.tenants.map(t => ({
    value: t.id,
    label: t.name,
    sublabel: t.currentUnitNumber ? `Current: Unit ${t.currentUnitNumber}` : 'No Unit Assigned'
  }))
})

const vacantUnitSelectOptions = computed(() => {
  return availableUnits.value.map(u => ({
    value: u.id,
    label: `Unit ${u.unitNumber} (${u.type})`,
    sublabel: `${formatKES(getUnitMonthlyRent(u))}/mo`
  }))
})

async function handleExecute() {
  error.value = ''
  if (!currentTenant.value || !currentUnit.value || !destinationUnit.value) {
    error.value = 'Please select a resident and vacant destination unit.'
    return
  }

  try {
    isSubmitting.value = true
    await executeUnitTransfer({
      tenantId: currentTenant.value.id,
      currentUnitId: currentUnit.value.id,
      newUnitId: destinationUnit.value.id,
      transferDate: transferDate.value,
      newRent: destinationRent.value,
      depositRollOver: depositRollOver.value,
      transferFee: 0,
      transferNotes: transferNotes.value || `Internal unit transfer to Unit ${destinationUnit.value.unitNumber}`
    })

    emit('transferred')
    emit('close')
  } catch (e: any) {
    error.value = e?.message || 'Transfer failed.'
  } finally {
    isSubmitting.value = false
  }
}
</script>

<template>
  <SideSheet
    :open="open"
    title="Internal Unit Transfer"
    subtitle="Reassign a resident to a new unit without corrupting historical records."
    @close="emit('close')"
  >
    <form @submit.prevent="handleExecute">
      <div v-if="error" style="padding: 10px 12px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.82rem; margin-bottom: 14px;">
        {{ error }}
      </div>

      <div class="form-field">
        <label>Resident</label>
        <SearchableSelect
          v-model="selectedTenantId"
          :options="tenantSelectOptions"
          placeholder="Select resident..."
          search-placeholder="Search resident..."
        />
      </div>

      <!-- Current Unit vs Destination Unit Comparison -->
      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 16px;">
        <div style="background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 12px;">
          <small style="color: #64748b; font-weight: 600; text-transform: uppercase; font-size: 0.72rem;">Current Unit</small>
          <strong style="display: block; font-size: 1rem; color: #172033; margin-top: 2px;">
            Unit {{ currentUnit?.unitNumber }}
          </strong>
          <span style="font-size: 0.8rem; color: #64748b;">
            {{ formatKES(currentRent) }}/mo · {{ currentUnit?.type }}
          </span>
        </div>

        <div style="background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 6px; padding: 12px;">
          <small style="color: #1d4ed8; font-weight: 600; text-transform: uppercase; font-size: 0.72rem;">Destination Unit</small>
          <div style="margin-top: 4px;">
            <SearchableSelect
              v-model="selectedNewUnitId"
              :options="vacantUnitSelectOptions"
              placeholder="Select vacant unit..."
              search-placeholder="Search vacant units..."
            />
          </div>
          <span v-if="destinationUnit" style="display: block; font-size: 0.8rem; color: #1e40af; margin-top: 6px;">
            {{ destinationUnit.type }} · {{ formatKES(destinationRent) }}/mo
          </span>
        </div>
      </div>

      <div class="form-row">
        <div class="form-field">
          <label>Transfer Effective Date</label>
          <input v-model="transferDate" type="date" required />
        </div>
        <div class="form-field">
          <label>Rent Differential</label>
          <input
            :value="`${rentDiff >= 0 ? '+' : ''}${formatKES(rentDiff)}/mo`"
            type="text"
            disabled
            style="background: #f8fafc; font-weight: 600;"
          />
        </div>
      </div>

      <div style="background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 12px; margin-bottom: 16px;">
        <label style="display: flex; align-items: center; gap: 8px; cursor: pointer; font-size: 0.82rem; margin: 0; font-weight: 600; color: #172033;">
          <input v-model="depositRollOver" type="checkbox" style="width: auto; margin: 0;" />
          <span>Roll over existing security deposit to new unit lease</span>
        </label>
      </div>

      <div class="form-field">
        <label>Transfer Notes</label>
        <textarea v-model="transferNotes" rows="2" placeholder="Reason for internal unit transfer..."></textarea>
      </div>

      <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 24px; padding-top: 16px; border-top: 1px solid #eef2f6;">
        <button type="button" class="secondary-button" @click="emit('close')">
          Cancel
        </button>
        <button type="submit" class="primary-button" :disabled="isSubmitting || !destinationUnit">
          <ArrowRightLeft :size="15" /> Execute Transfer
        </button>
      </div>
    </form>
  </SideSheet>
</template>
