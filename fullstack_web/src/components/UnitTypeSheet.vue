<script setup lang="ts">
import { ref, watch } from 'vue'
import { Save } from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import { saveUnitTypeConfig } from '../data'
import type { UnitTypeConfig } from '../types'

const props = defineProps<{
  open: boolean
  unitType: UnitTypeConfig | null
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'saved'): void
}>()

const name = ref('')
const baseRent = ref(0)
const depositMultiplier = ref(1.0)
const description = ref('')
const features = ref('')
const error = ref('')

watch(
  () => props.unitType,
  (ut) => {
    error.value = ''
    if (ut) {
      name.value = ut.name
      baseRent.value = ut.baseRent
      depositMultiplier.value = ut.depositMultiplier
      description.value = ut.description
      features.value = (ut.features || []).join(', ')
    } else {
      name.value = ''
      baseRent.value = 0
      depositMultiplier.value = 1.0
      description.value = ''
      features.value = ''
    }
  },
  { immediate: true }
)

async function handleSave() {
  if (!name.value.trim()) {
    error.value = 'Display name is required.'
    return
  }
  if (!baseRent.value || baseRent.value <= 0) {
    error.value = 'Valid base monthly rent is required.'
    return
  }

  try {
    await saveUnitTypeConfig({
      id: props.unitType?.id,
      name: name.value.trim(),
      baseRent: Number(baseRent.value),
      depositMultiplier: Number(depositMultiplier.value || 1),
      description: description.value.trim(),
      features: features.value.split(',').map(f => f.trim()).filter(Boolean)
    })
    emit('saved')
    emit('close')
  } catch (e: any) {
    error.value = e?.message || 'Failed to save unit type.'
  }
}
</script>

<template>
  <SideSheet
    :open="open"
    :title="unitType ? 'Edit Unit Type' : 'Add Unit Type'"
    subtitle="Configure display name, base rent, deposit multiplier, description, and features."
    @close="emit('close')"
  >
    <form @submit.prevent="handleSave">
      <div v-if="error" style="padding: 10px 12px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.82rem; margin-bottom: 14px;">
        {{ error }}
      </div>

      <div class="form-field">
        <label>Display Name *</label>
        <input v-model="name" required placeholder="e.g. Studio Executive" />
      </div>

      <div class="form-row">
        <div class="form-field">
          <label>Base Monthly Rent (KES) *</label>
          <input v-model.number="baseRent" type="number" min="10" required />
        </div>

        <div class="form-field">
          <label>Deposit Multiplier (x Months) *</label>
          <input v-model.number="depositMultiplier" type="number" step="0.5" min="0" required />
        </div>
      </div>

      <div class="form-field">
        <label>Description</label>
        <textarea v-model="description" rows="2" placeholder="Brief unit description..."></textarea>
      </div>

      <div class="form-field">
        <label>Features (Comma Separated)</label>
        <textarea
          v-model="features"
          rows="3"
          placeholder="e.g. Fiber Internet, Balcony, En-suite Bathroom, Reserved Parking"
        ></textarea>
      </div>

      <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 24px; padding-top: 16px; border-top: 1px solid #eef2f6;">
        <button type="button" class="secondary-button" @click="emit('close')">
          Cancel
        </button>
        <button type="submit" class="primary-button">
          <Save :size="15" /> Save Unit Type
        </button>
      </div>
    </form>
  </SideSheet>
</template>