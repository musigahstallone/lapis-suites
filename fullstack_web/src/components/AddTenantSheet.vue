<script setup lang="ts">
import { ref } from 'vue'
import { Users, Plus } from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import { createTenant } from '../data'

const props = defineProps<{
  open: boolean
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'created'): void
}>()

const name = ref('')
const email = ref('')
const phone = ref('')
const nationalId = ref('')
const emergencyContact = ref('')
const error = ref('')

async function handleSave() {
  if (!name.value.trim()) {
    error.value = 'Full name is required.'
    return
  }
  if (!phone.value.trim()) {
    error.value = 'Phone number is required.'
    return
  }

  try {
    await createTenant({
      name: name.value.trim(),
      email: email.value.trim() || `${name.value.toLowerCase().replace(/\s+/g, '.')}@example.com`,
      phone: phone.value.trim(),
      nationalId: nationalId.value.trim() || undefined,
      emergencyContact: emergencyContact.value.trim() || undefined
    })

    name.value = ''
    email.value = ''
    phone.value = ''
    nationalId.value = ''
    emergencyContact.value = ''
    emit('created')
    emit('close')
  } catch (e: any) {
    error.value = e?.message || 'Failed to add tenant.'
  }
}
</script>

<template>
  <SideSheet
    :open="open"
    title="Register Tenant"
    subtitle="Create a new resident record in the Lapis Suites directory."
    @close="emit('close')"
  >
    <form @submit.prevent="handleSave">
      <div v-if="error" style="padding: 10px 12px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.82rem; margin-bottom: 14px;">
        {{ error }}
      </div>

      <div class="form-field">
        <label>Full Legal Name</label>
        <input v-model="name" required placeholder="e.g. Samuel Kamau" />
      </div>

      <div class="form-row">
        <div class="form-field">
          <label>Phone Number (M-Pesa ID)</label>
          <input v-model="phone" required placeholder="+254 7XX XXX XXX" />
        </div>
        <div class="form-field">
          <label>Email Address</label>
          <input v-model="email" type="email" placeholder="tenant@example.com" />
        </div>
      </div>

      <div class="form-row">
        <div class="form-field">
          <label>National ID / Passport</label>
          <input v-model="nationalId" placeholder="ID-XXXXXXX" />
        </div>
        <div class="form-field">
          <label>Emergency Contact</label>
          <input v-model="emergencyContact" placeholder="+254 7XX... (Next of kin)" />
        </div>
      </div>

      <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 24px; padding-top: 16px; border-top: 1px solid #eef2f6;">
        <button type="button" class="secondary-button" @click="emit('close')">
          Cancel
        </button>
        <button type="submit" class="primary-button">
          <Plus :size="15" /> Save Resident
        </button>
      </div>
    </form>
  </SideSheet>
</template>
