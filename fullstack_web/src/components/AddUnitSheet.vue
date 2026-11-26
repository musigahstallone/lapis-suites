<script setup lang="ts">
import { ref, computed } from 'vue'
import { Building2, Plus, Info, CheckCircle2 } from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import { store, createUnit, formatKES, getUnitFeatures } from '../data'
import type { UnitType } from '../types'

const props = defineProps<{
  open: boolean
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'created'): void
}>()

const unitNumber = ref('')
const type = ref<UnitType>('studio')
const status = ref<'vacant' | 'maintenance'>('vacant')
const error = ref('')

const selectedUnitTypeConfig = computed(() => {
  return store.unitTypes.find(ut => ut.key === type.value)
})

const inheritedFeatures = computed(() => {
  return getUnitFeatures(type.value)
})

async function handleSave() {
  if (!unitNumber.value.trim()) {
    error.value = 'Unit number or name is required.'
    return
  }

  try {
    await createUnit({
      unitNumber: unitNumber.value.trim().toUpperCase(),
      type: type.value,
      status: status.value
    })

    unitNumber.value = ''
    emit('created')
    emit('close')
  } catch (e: any) {
    error.value = e?.message || 'Failed to add unit.'
  }
}
</script>

<template>
  <SideSheet
    :open="open"
    title="Add Unit"
    subtitle="Register a new apartment unit. Specifications are inherited from Unit Type."
    @close="emit('close')"
  >
    <form @submit.prevent="handleSave">
      <div v-if="error" style="padding: 10px 12px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.84rem; margin-bottom: 14px;">
        {{ error }}
      </div>

      <div class="form-field">
        <label>Unit Name / Number *</label>
        <input v-model="unitNumber" required placeholder="e.g. 104, 205B, or Executive 1" />
      </div>

      <div class="form-row">
        <div class="form-field">
          <label>Unit Type *</label>
          <select v-model="type">
            <option v-for="ut in store.unitTypes" :key="ut.id" :value="ut.key">
              {{ ut.name }} ({{ formatKES(ut.baseRent) }}/mo)
            </option>
          </select>
        </div>

        <div class="form-field">
          <label>Initial Status *</label>
          <select v-model="status">
            <option value="vacant">Vacant</option>
            <option value="maintenance">Maintenance</option>
          </select>
        </div>
      </div>

      <!-- Inherited Specifications Box -->
      <div style="background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; margin-top: 14px; margin-bottom: 16px;">
        <div style="display: flex; align-items: center; gap: 6px; font-size: 0.84rem; font-weight: 700; color: #1e3a8a; margin-bottom: 6px;">
          <Info :size="15" /> Inherited from {{ selectedUnitTypeConfig?.name }}
        </div>
        <p style="font-size: 0.78rem; color: #64748b; margin-bottom: 10px;">
          All features and baseline pricing are centrally defined on the Unit Type configuration and inherited automatically.
        </p>

        <div style="display: flex; justify-content: space-between; font-size: 0.82rem; margin-bottom: 8px;">
          <span style="color: #64748b;">Standard Monthly Rent:</span>
          <strong style="color: #059669;">{{ formatKES(selectedUnitTypeConfig?.baseRent || 0) }}/mo</strong>
        </div>

        <div style="font-size: 0.78rem; font-weight: 600; color: #475467; margin-bottom: 6px;">
          Inherited Amenities & Features:
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

      <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 24px; padding-top: 16px; border-top: 1px solid #eef2f6;">
        <button type="button" class="secondary-button" @click="emit('close')">
          Cancel
        </button>
        <button type="submit" class="primary-button">
          <Plus :size="15" /> Save Unit
        </button>
      </div>
    </form>
  </SideSheet>
</template>
