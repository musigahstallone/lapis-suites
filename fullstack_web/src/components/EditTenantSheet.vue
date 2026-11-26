<script setup lang="ts">
import { ref, watch } from 'vue'
import { Save, Trash2 } from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import { updateTenant, deleteTenant } from '../data'
import type { Tenant } from '../types'

const props = defineProps<{
  open: boolean
  tenant: Tenant | null
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'updated'): void
  (e: 'deleted'): void
}>()

const name = ref('')
const email = ref('')
const phone = ref('')
const nationalId = ref('')
const emergencyContact = ref('')
const error = ref('')

watch(
  () => props.tenant,
  (t) => {
    if (t) {
      name.value = t.name
      email.value = t.email
      phone.value = t.phone
      nationalId.value = t.nationalId || ''
      emergencyContact.value = t.emergencyContact || ''
    }
  },
  { immediate: true }
)

async function handleSave() {
  if (!props.tenant) return
  try {
    await updateTenant(props.tenant.id, {
      name: name.value.trim(),
      email: email.value.trim(),
      phone: phone.value.trim(),
      nationalId: nationalId.value.trim() || undefined,
      emergencyContact: emergencyContact.value.trim() || undefined
    })
    emit('updated')
    emit('close')
  } catch (e: any) {
    error.value = e?.message || 'Failed to update resident.'
  }
}

async function handleDelete() {
  if (!props.tenant) return
  if (confirm(`Remove resident record for ${props.tenant.name}?`)) {
    try {
      await deleteTenant(props.tenant.id)
      emit('deleted')
      emit('close')
    } catch (e: any) {
      error.value = e?.message || 'Cannot delete resident.'
    }
  }
}
</script>

<template>
  <SideSheet
    :open="open"
    title="Edit Resident Record"
    :subtitle="tenant ? `Unit: ${tenant.currentUnitNumber}` : ''"
    @close="emit('close')"
  >
    <form v-if="tenant" @submit.prevent="handleSave">
      <div v-if="error" style="padding: 10px 12px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.82rem; margin-bottom: 14px;">
        {{ error }}
      </div>

      <div class="form-field">
        <label>Full Legal Name</label>
        <input v-model="name" required />
      </div>

      <div class="form-row">
        <div class="form-field">
          <label>Phone Number (M-Pesa)</label>
          <input v-model="phone" required />
        </div>
        <div class="form-field">
          <label>Email Address</label>
          <input v-model="email" type="email" required />
        </div>
      </div>

      <div class="form-row">
        <div class="form-field">
          <label>National ID / Passport</label>
          <input v-model="nationalId" />
        </div>
        <div class="form-field">
          <label>Emergency Contact</label>
          <input v-model="emergencyContact" />
        </div>
      </div>

      <div style="margin-top: 24px; padding-top: 16px; border-top: 1px solid #eef2f6; display: flex; align-items: center; justify-content: space-between;">
        <button
          v-if="!tenant.currentUnitId"
          type="button"
          class="danger-button"
          style="min-height: 32px; font-size: 0.8rem; padding: 0 10px;"
          @click="handleDelete"
        >
          <Trash2 :size="13" /> Delete Record
        </button>
        <span v-else style="font-size: 0.76rem; color: #64748b;">
          Assigned to Unit {{ tenant.currentUnitNumber }}
        </span>

        <div style="display: flex; gap: 8px;">
          <button type="button" class="secondary-button" @click="emit('close')">
            Cancel
          </button>
          <button type="submit" class="primary-button">
            <Save :size="15" /> Save Changes
          </button>
        </div>
      </div>
    </form>
  </SideSheet>
</template>
