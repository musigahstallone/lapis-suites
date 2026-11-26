<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { User, Save, CheckCircle2, ShieldCheck, Lock, AlertCircle, Phone } from 'lucide-vue-next'
import { store, updateTenant } from '../../data'

const resident = computed(() => {
  return (
    store.tenants.find(t => t.id === store.session.tenantId || t.id === store.session.id) ||
    store.tenants.find(t => store.session.email && t.email && t.email.toLowerCase() === store.session.email.toLowerCase()) ||
    store.tenants[0]
  )
})

const email = ref(resident.value?.email || '')
const otherPhone = ref(resident.value?.otherPhone || resident.value?.emergencyContact || '')
const saved = ref(false)
const error = ref('')
const isSaving = ref(false)

watch(resident, (r) => {
  if (r) {
    email.value = r.email || ''
    otherPhone.value = r.otherPhone || r.emergencyContact || ''
  }
}, { immediate: true })

async function handleSave() {
  if (!resident.value) return
  error.value = ''
  isSaving.value = true

  try {
    // Tenants can strictly edit their email and alternative/other numbers only
    await updateTenant(resident.value.id, {
      email: email.value.trim().toLowerCase(),
      otherPhone: otherPhone.value.trim()
    })

    saved.value = true
    setTimeout(() => {
      saved.value = false
    }, 3000)
  } catch (err: any) {
    error.value = err.message || 'Failed to update profile details.'
  } finally {
    isSaving.value = false
  }
}
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">RESIDENT SETTINGS</p>
        <h1>Profile & Preferences</h1>
        <p>Manage your contact details and active notification preferences for Lapis Suites.</p>
      </div>

      <div class="intro-actions">
        <button class="primary-button" :disabled="isSaving" @click="handleSave">
          <Save :size="15" />
          <span>{{ isSaving ? 'Saving...' : 'Save Changes' }}</span>
        </button>
      </div>
    </header>

    <div v-if="saved" style="padding: 12px 16px; background: #ecfdf5; border: 1px solid #a7f3d0; color: #047857; border-radius: 8px; font-size: 0.86rem; margin-bottom: 20px; display: flex; align-items: center; gap: 8px; font-weight: 500;">
      <CheckCircle2 :size="16" />
      <span>Contact preferences updated successfully.</span>
    </div>

    <div v-if="error" style="padding: 12px 16px; background: #fef2f2; border: 1px solid #fee2e2; color: #b91c1c; border-radius: 8px; font-size: 0.86rem; margin-bottom: 20px; display: flex; align-items: center; gap: 8px;">
      <AlertCircle :size="16" />
      <span>{{ error }}</span>
    </div>

    <div style="max-width: 680px;">
      <!-- Administrative Notice Banner -->
      <div style="padding: 12px 16px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 20px; display: flex; align-items: flex-start; gap: 10px;">
        <ShieldCheck :size="18" style="color: #64748b; flex: none; margin-top: 2px;" />
        <p style="font-size: 0.82rem; color: #64748b; margin: 0; line-height: 1.45;">
          <strong>Identity Safeguard:</strong> Full legal name, official national identification, and primary payment phone number are verified under your tenancy agreement and can only be updated by property management.
        </p>
      </div>

      <form class="panel" style="padding: 24px;" @submit.prevent="handleSave">
        <!-- Section 1: Tenant Editable Contact Channels -->
        <h3 style="font-size: 0.95rem; font-weight: 700; color: #0f172a; margin: 0 0 16px 0; display: flex; align-items: center; gap: 8px;">
          <span>Editable Contact Details</span>
        </h3>

        <div class="form-row">
          <div class="form-field">
            <label>Email Address (For receipts & notices)</label>
            <input
              v-model="email"
              type="email"
              required
              placeholder="e.g. resident@example.com"
            />
          </div>

          <div class="form-field">
            <label>Other Numbers / Alternative Contact</label>
            <input
              v-model="otherPhone"
              type="tel"
              placeholder="e.g. +254 700 000 000"
            />
            <small style="color: #64748b; font-size: 0.76rem; margin-top: 4px;">
              Secondary phone or emergency contact number.
            </small>
          </div>
        </div>

        <div style="margin: 24px 0 20px 0; border-top: 1px solid #eef2f6;"></div>

        <!-- Section 2: Verified Tenancy Identity (Managed by Landlord) -->
        <h3 style="font-size: 0.95rem; font-weight: 700; color: #475569; margin: 0 0 6px 0; display: flex; align-items: center; justify-content: space-between;">
          <div style="display: flex; align-items: center; gap: 8px;">
            <Lock :size="14" style="color: #94a3b8;" />
            <span>Verified Tenancy Identity</span>
          </div>
          <span class="badge" style="background: #f1f5f9; color: #475569; font-size: 0.72rem;">Landlord Verified</span>
        </h3>
        <p style="font-size: 0.80rem; color: #64748b; margin: 0 0 16px 0;">
          To request an official name, national ID, or primary phone change, contact management.
        </p>

        <div class="form-row">
          <div class="form-field">
            <label>Full Legal Name</label>
            <input
              :value="resident?.name"
              readonly
              disabled
              style="background: #f8fafc; color: #64748b; cursor: not-allowed;"
            />
          </div>

          <div class="form-field">
            <label>Assigned Unit</label>
            <input
              :value="resident?.currentUnitNumber ? `Unit ${resident?.currentUnitNumber}` : 'Unassigned'"
              readonly
              disabled
              style="background: #f8fafc; color: #64748b; cursor: not-allowed;"
            />
          </div>
        </div>

        <div class="form-row">
          <div class="form-field">
            <label>Primary Phone Number (M-Pesa STK)</label>
            <input
              :value="resident?.phone"
              readonly
              disabled
              style="background: #f8fafc; color: #64748b; cursor: not-allowed;"
            />
          </div>

          <div class="form-field">
            <label>National ID / Passport Number</label>
            <input
              :value="resident?.nationalId || 'Verified on file'"
              readonly
              disabled
              style="background: #f8fafc; color: #64748b; cursor: not-allowed;"
            />
          </div>
        </div>

        <div style="margin-top: 24px; padding-top: 16px; border-top: 1px solid #eef2f6; display: flex; justify-content: flex-end;">
          <button type="submit" class="primary-button" :disabled="isSaving">
            <Save :size="15" />
            <span>{{ isSaving ? 'Saving...' : 'Save Profile' }}</span>
          </button>
        </div>
      </form>
    </div>
  </div>
</template>
