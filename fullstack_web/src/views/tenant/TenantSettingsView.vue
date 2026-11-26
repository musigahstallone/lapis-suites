<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { User, Save, CheckCircle2, ShieldCheck, Lock, AlertCircle, Phone, KeyRound, LogOut } from 'lucide-vue-next'
import { store, updateTenant, changeMyPassword, logoutAllDevices, logout } from '../../data'

const router = useRouter()

const resident = computed(() => {
  return (
    store.tenants.find(t => store.session.email && t.email && t.email.toLowerCase() === store.session.email.toLowerCase()) ||
    store.tenants.find(t => store.session.tenantId && t.id === store.session.tenantId) ||
    store.tenants.find(t => store.session.id && t.id === store.session.id) ||
    null
  )
})

const email = ref(resident.value?.email || '')
const otherPhone = ref(resident.value?.otherPhone || resident.value?.emergencyContact || '')
const saved = ref(false)
const error = ref('')
const isSaving = ref(false)

// Security controls (Change Password & Sign Out All Devices)
const currentPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const isUpdatingPassword = ref(false)
const passwordError = ref('')
const passwordSuccess = ref('')
const isRevokingAll = ref(false)

async function handleChangePassword() {
  passwordError.value = ''
  passwordSuccess.value = ''
  if (!currentPassword.value || !newPassword.value) {
    passwordError.value = 'Enter your current password and a new password.'
    return
  }
  if (newPassword.value.length < 6) {
    passwordError.value = 'New password must be at least 6 characters.'
    return
  }
  if (newPassword.value !== confirmPassword.value) {
    passwordError.value = 'New passwords do not match.'
    return
  }
  isUpdatingPassword.value = true
  try {
    await changeMyPassword({
      currentPassword: currentPassword.value,
      newPassword: newPassword.value,
      confirmPassword: confirmPassword.value
    })
    currentPassword.value = ''
    newPassword.value = ''
    confirmPassword.value = ''
    passwordSuccess.value = 'Password updated and other sessions revoked.'
    setTimeout(() => { passwordSuccess.value = '' }, 4000)
  } catch (err: any) {
    passwordError.value = err.message || 'Could not update password.'
  } finally {
    isUpdatingPassword.value = false
  }
}

async function handleLogoutAll() {
  isRevokingAll.value = true
  try {
    await logoutAllDevices()
    logout()
    router.push('/login')
  } catch (err: any) {
    passwordError.value = err.message || 'Could not sign out all devices.'
  } finally {
    isRevokingAll.value = false
  }
}

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

      <!-- Account Security Card -->
      <section class="panel" style="padding: 24px; margin-top: 20px;">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; flex-wrap: wrap; gap: 10px;">
          <div>
            <h3 style="font-size: 0.95rem; font-weight: 700; color: #0f172a; margin: 0; display: flex; align-items: center; gap: 8px;">
              <KeyRound :size="16" style="color: #0f172a;" />
              <span>Password &amp; Sessions</span>
            </h3>
            <p style="font-size: 0.80rem; color: #64748b; margin: 4px 0 0 0;">
              Changing your password signs out all other devices automatically.
            </p>
          </div>
          <button type="button" class="secondary-button" :disabled="isRevokingAll" @click="handleLogoutAll">
            <LogOut :size="14" />
            <span>{{ isRevokingAll ? 'Signing out...' : 'Sign Out All Devices' }}</span>
          </button>
        </div>

        <div v-if="passwordSuccess" style="padding: 10px 14px; background: #ecfdf5; border: 1px solid #a7f3d0; color: #047857; border-radius: 8px; font-size: 0.83rem; margin-bottom: 14px;">
          {{ passwordSuccess }}
        </div>
        <div v-if="passwordError" style="padding: 10px 14px; background: #fef2f2; border: 1px solid #fee2e2; color: #b91c1c; border-radius: 8px; font-size: 0.83rem; margin-bottom: 14px;">
          {{ passwordError }}
        </div>

        <form @submit.prevent="handleChangePassword">
          <div class="form-field">
            <label>Current Password</label>
            <input v-model="currentPassword" type="password" required placeholder="Enter current password" />
          </div>
          <div class="form-row">
            <div class="form-field">
              <label>New Password</label>
              <input v-model="newPassword" type="password" required minlength="6" placeholder="At least 6 characters" />
            </div>
            <div class="form-field">
              <label>Confirm New Password</label>
              <input v-model="confirmPassword" type="password" required minlength="6" placeholder="Re-enter new password" />
            </div>
          </div>
          <div style="display: flex; justify-content: flex-end; margin-top: 12px;">
            <button type="submit" class="primary-button" :disabled="isUpdatingPassword">
              <KeyRound :size="14" />
              <span>{{ isUpdatingPassword ? 'Updating...' : 'Update Password' }}</span>
            </button>
          </div>
        </form>
      </section>
    </div>
  </div>
</template>
