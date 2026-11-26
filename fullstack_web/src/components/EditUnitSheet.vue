<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import { Save, Trash2, Info, Building2, Lock } from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import { store, updateUnit, deleteUnit, formatKES, getUnitFeatures } from '../data'
import type { Unit, UnitType, UnitStatus } from '../types'

const props = defineProps<{
  open: boolean
  unit: Unit | null
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'updated'): void
  (e: 'deleted'): void
}>()

const unitNumber = ref('')
const type = ref<UnitType>('studio')
const status = ref<UnitStatus>('vacant')
const error = ref('')

const isOccupied = computed(() => {
  return props.unit?.status === 'occupied' || Boolean(props.unit?.currentTenantId)
})

watch(
  () => props.unit,
  (u) => {
    if (u) {
      unitNumber.value = u.unitNumber
      type.value = u.type
      status.value = u.status
    }
  },
  { immediate: true }
)

const selectedUnitTypeConfig = computed(() => {
  return store.unitTypes.find(ut => ut.key === type.value)
})

const inheritedFeatures = computed(() => {
  return getUnitFeatures(type.value)
})

async function handleSave() {
  if (!props.unit) return
  error.value = ''

  try {
    await updateUnit(props.unit.id, {
      type: type.value
    })
    emit('updated')
    emit('close')
  } catch (e: any) {
    error.value = e?.message || 'Failed to update unit.'
  }
}

async function handleDelete() {
  if (!props.unit) return
  if (confirm(`Remove Unit ${props.unit.unitNumber} from inventory?`)) {
    try {
      await deleteUnit(props.unit.id)
      emit('deleted')
      emit('close')
    } catch (e: any) {
      error.value = e?.message || 'Cannot delete unit.'
    }
  }
}
</script>

<template>
  <SideSheet
    :open="open"
    title="Edit Unit"
    :subtitle="unit ? `Unit ${unit.unitNumber} (${unit.type})` : ''"
    @close="emit('close')"
  >
    <form v-if="unit" @submit.prevent="handleSave">
      <div v-if="error" style="padding: 10px 12px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.84rem; margin-bottom: 14px;">
        {{ error }}
      </div>

      <!-- Immutable Unit Identifier -->
      <div class="form-field">
        <label style="display: flex; align-items: center; justify-content: space-between;">
          <span>Unit Number (Immutable)</span>
          <span style="display: inline-flex; align-items: center; gap: 4px; font-size: 0.72rem; color: #64748b;">
            <Lock :size="12" /> System Identifier
          </span>
        </label>
        <input
          :value="unitNumber"
          disabled
          style="background: #f8fafc; color: #64748b; font-family: 'Google Sans Code', monospace; font-weight: 700; cursor: not-allowed;"
        />
        <small style="color: #64748b; font-size: 0.74rem; margin-top: 3px; display: block;">
          Protected by data integrity guard. Unit identifiers cannot be altered after creation.
        </small>
      </div>

      <div class="form-row">
        <div class="form-field">
          <label>Unit Type</label>
          <select v-model="type" :disabled="isOccupied">
            <option v-for="ut in store.unitTypes" :key="ut.id" :value="ut.key">
              {{ ut.name }}
            </option>
          </select>
          <small v-if="isOccupied" style="color: #64748b; font-size: 0.72rem; margin-top: 3px; display: block;">
            Unit type is locked while occupied under an active lease.
          </small>
        </div>

        <div class="form-field">
          <label>Status (Lease-Managed)</label>
          <input
            :value="status === 'occupied' ? 'Occupied' : 'Vacant'"
            disabled
            style="background: #f8fafc; color: #64748b; font-weight: 600; cursor: not-allowed;"
          />
          <small style="color: #64748b; font-size: 0.72rem; margin-top: 3px; display: block;">
            Status cannot be edited manually — assign or end a lease instead.
          </small>
        </div>
      </div>

      <!-- Inherited Specifications Box -->
      <div style="background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; margin-top: 14px; margin-bottom: 16px;">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px;">
          <div style="display: flex; align-items: center; gap: 6px; font-size: 0.84rem; font-weight: 700; color: #1e3a8a;">
            <Info :size="15" /> Inherited from {{ selectedUnitTypeConfig?.name }}
          </div>
          <span class="badge active" style="font-size: 0.72rem;">Centralized</span>
        </div>
        <p style="font-size: 0.78rem; color: #64748b; margin-bottom: 10px;">
          All unit features and baseline pricing come directly from the Unit Type configuration and are only editable in Unit Types Configuration.
        </p>

        <div style="display: flex; justify-content: space-between; font-size: 0.84rem; margin-bottom: 8px;">
          <span style="color: #64748b;">Base Monthly Rent:</span>
          <strong style="color: #059669;">{{ formatKES(selectedUnitTypeConfig?.baseRent || 0) }}/mo</strong>
        </div>

        <div style="font-size: 0.78rem; font-weight: 600; color: #475467; margin-bottom: 6px;">
          Inherited Features:
        </div>
        <div style="display: flex; flex-wrap: wrap; gap: 6px;">
          <span
            v-for="(f, idx) in inheritedFeatures"
            :key="idx"
            class="badge"
            style="background: #ffffff; border: 1px solid #cbd5e1; color: #334155; font-size: 0.75rem;"
          >
            ✓ {{ f }}
          </span>
        </div>
      </div>

      <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 24px; padding-top: 16px; border-top: 1px solid #eef2f6;">
        <button
          v-if="!isOccupied"
          type="button"
          class="secondary-button"
          style="color: #b91c1c; border-color: #fecaca;"
          @click="handleDelete"
        >
          <Trash2 :size="14" /> Delete
        </button>
        <div v-else></div>

        <div style="display: flex; gap: 8px;">
          <button type="button" class="secondary-button" @click="emit('close')">
            Cancel
          </button>
          <button type="submit" class="primary-button">
            <Save :size="14" /> Save Changes
          </button>
        </div>
      </div>
    </form>
  </SideSheet>
</template>
