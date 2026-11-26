<script setup lang="ts">
import { ref, onMounted } from 'vue'
import {
  Building2,
  CheckCircle2,
  Save,
  UploadCloud,
  FileSpreadsheet,
  AlertCircle,
  Copy,
  Check,
  Edit2,
  Users,
  Calendar,
  Smartphone,
  ShieldCheck,
  KeyRound,
  LogOut
} from 'lucide-vue-next'
import { useRouter } from 'vue-router'
import {
  propertyInfo,
  propertySettings,
  store,
  fetchUnits,
  fetchTenants,
  fetchLeases,
  fetchPayments,
  fetchAppSettings,
  saveAppSettings,
  changeMyPassword,
  logoutAllDevices,
  logout,
  type AdminAccountSetting
} from '../data'
import SideSheet from '../components/SideSheet.vue'
import PhoneInput from '../components/PhoneInput.vue'

const router = useRouter()
const isSavingSettings = ref(false)
const savedMessage = ref('')
const settingsError = ref('')

// Account Security State
const isPasswordSheetOpen = ref(false)
const currentPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const passwordError = ref('')
const isUpdatingPassword = ref(false)
const isRevokingAll = ref(false)

async function handleChangePassword() {
  passwordError.value = ''
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
    isPasswordSheetOpen.value = false
    currentPassword.value = ''
    newPassword.value = ''
    confirmPassword.value = ''
    savedMessage.value = 'Password updated and prior sessions revoked.'
    setTimeout(() => { savedMessage.value = '' }, 4000)
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
    settingsError.value = err.message || 'Could not sign out all devices.'
  } finally {
    isRevokingAll.value = false
  }
}

// Authorized Admins list (read-only display on page; edited in SideSheet)
const admins = ref<AdminAccountSetting[]>([])

// SideSheets
const isPropertySheetOpen = ref(false)
const isAdminSheetOpen = ref(false)
const isImportSheetOpen = ref(false)

// Edit buffers for SideSheets
const propertyDraft = ref({
  propertyName: '',
  address: '',
  city: '',
  totalFloors: 14,
  managerName: '',
  contactPhone: '',
  contactEmail: '',
  paybillNumber: '',
  rentDueDay: 5,
  gracePeriodDays: 5
})

const editingAdminIndex = ref<number>(-1)
const adminDraft = ref<AdminAccountSetting>({
  id: undefined,
  name: '',
  email: '',
  phone: ''
})

async function loadSettings() {
  const data = await fetchAppSettings()
  if (data?.admins) {
    admins.value = data.admins.slice(0, 2).map((a: any) => ({
      id: a.id,
      name: a.name || 'Administrator',
      email: a.email || '',
      phone: a.phone || ''
    }))
  }
}

onMounted(async () => {
  await loadSettings()
})

function openPropertySheet() {
  settingsError.value = ''
  propertyDraft.value = {
    propertyName: propertyInfo.name,
    address: propertyInfo.address,
    city: propertyInfo.city,
    totalFloors: propertyInfo.totalFloors,
    managerName: propertyInfo.managerName,
    contactPhone: propertyInfo.contactPhone,
    contactEmail: propertyInfo.contactEmail,
    paybillNumber: propertyInfo.paybillNumber,
    rentDueDay: propertySettings.rentDueDay,
    gracePeriodDays: propertySettings.gracePeriodDays
  }
  isPropertySheetOpen.value = true
}

async function handleSaveProperty() {
  settingsError.value = ''
  isSavingSettings.value = true
  try {
    await saveAppSettings({
      settings: {
        ...propertyDraft.value,
        lateFeePercent: propertySettings.lateFeePercent,
        autoReconciliationEnabled: propertySettings.autoReconciliationEnabled
      }
    })
    isPropertySheetOpen.value = false
    savedMessage.value = 'Property & billing settings updated.'
    setTimeout(() => { savedMessage.value = '' }, 3000)
  } catch (err: any) {
    settingsError.value = err.message || 'Failed to save property settings.'
  } finally {
    isSavingSettings.value = false
  }
}

function openEditAdminSheet(index: number) {
  settingsError.value = ''
  editingAdminIndex.value = index
  const target = admins.value[index] || { id: undefined, name: '', email: '', phone: '' }
  adminDraft.value = { ...target }
  isAdminSheetOpen.value = true
}

async function handleSaveAdmin() {
  settingsError.value = ''
  if (!adminDraft.value.email.trim()) {
    settingsError.value = 'Email address is required.'
    return
  }

  const nextAdmins = [...admins.value]
  if (editingAdminIndex.value >= 0 && editingAdminIndex.value < nextAdmins.length) {
    nextAdmins[editingAdminIndex.value] = { ...adminDraft.value }
  } else if (nextAdmins.length < 2) {
    nextAdmins.push({ ...adminDraft.value })
  }

  isSavingSettings.value = true
  try {
    const res = await saveAppSettings({
      settings: {},
      admins: nextAdmins
    })
    if (res.admins) {
      admins.value = res.admins.slice(0, 2).map((a: any) => ({
        id: a.id,
        name: a.name || 'Administrator',
        email: a.email || '',
        phone: a.phone || ''
      }))
    }
    isAdminSheetOpen.value = false
    savedMessage.value = 'Administrator details updated.'
    setTimeout(() => { savedMessage.value = '' }, 3000)
  } catch (err: any) {
    settingsError.value = err.message || 'Failed to update administrator.'
  } finally {
    isSavingSettings.value = false
  }
}

// Bulk CSV Importer State (Inside SideSheet)
type ImportType = 'units' | 'tenants_leases' | 'transactions'
const importType = ref<ImportType>('units')
const rawCsv = ref('')
const parsedRows = ref<any[]>([])
const importError = ref('')
const importSuccess = ref('')
const isImporting = ref(false)
const copiedTemplate = ref(false)

const templates: Record<ImportType, string> = {
  units: `unitNumber,type,status
101,studio,vacant
102,studio,vacant
201,one-bedroom,vacant`,
  tenants_leases: `name,email,phone,nationalId,unitNumber,startDate,endDate,monthlyRent,depositAmount,depositPaid
James Mwangi,james.mwangi@example.com,254711223344,ID-12345678,101,2026-11-01,2027-10-31,42000,42000,true`,
  transactions: `reference,unitNumber,tenantName,amount,date,method,notes
QKD910281,101,James Mwangi,84000,2026-11-01,mpesa_paybill,November Rent and Deposit`
}

function handleCopyTemplate() {
  navigator.clipboard.writeText(templates[importType.value])
  copiedTemplate.value = true
  setTimeout(() => { copiedTemplate.value = false }, 2000)
}

function handlePasteTemplate() {
  rawCsv.value = templates[importType.value]
  handleParseCsv()
}

function handleFileUpload(event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0]
  if (!file) return
  const reader = new FileReader()
  reader.onload = (e) => {
    rawCsv.value = String(e.target?.result || '')
    handleParseCsv()
  }
  reader.readAsText(file)
}

function handleParseCsv() {
  importError.value = ''
  importSuccess.value = ''
  parsedRows.value = []

  const text = rawCsv.value.trim()
  if (!text) {
    importError.value = 'Paste CSV data or upload a CSV file.'
    return
  }

  const lines = text.split(/\r?\n/).map(l => l.trim()).filter(Boolean)
  if (lines.length < 2) {
    importError.value = 'CSV must include a header row and at least one data row.'
    return
  }

  const headers = lines[0].split(',').map(h => h.trim().replace(/^["']|["']$/g, ''))
  const rows: any[] = []
  for (let i = 1; i < lines.length; i++) {
    const values = lines[i].split(',').map(v => v.trim().replace(/^["']|["']$/g, ''))
    const rowObj: any = {}
    headers.forEach((h, idx) => { rowObj[h] = values[idx] !== undefined ? values[idx] : '' })
    rows.push(rowObj)
  }
  parsedRows.value = rows
}

async function handleExecuteImport() {
  if (parsedRows.value.length === 0) return
  isImporting.value = true
  importError.value = ''
  importSuccess.value = ''
  try {
    const token = store.session.token
    const headers: Record<string, string> = { 'Content-Type': 'application/json' }
    if (token) headers['Authorization'] = `Bearer ${token}`

    let endpoint = ''
    let bodyPayload: any = {}
    if (importType.value === 'units') {
      endpoint = '/api/import/units'
      bodyPayload = { units: parsedRows.value }
    } else if (importType.value === 'tenants_leases') {
      endpoint = '/api/import/tenants-leases'
      bodyPayload = { records: parsedRows.value }
    } else {
      endpoint = '/api/import/transactions'
      bodyPayload = { transactions: parsedRows.value }
    }

    const res = await fetch(endpoint, { method: 'POST', headers, body: JSON.stringify(bodyPayload) })
    const data = await res.json()
    if (!res.ok) {
      importError.value = data.error || 'Import failed.'
      return
    }

    if (importType.value === 'units') {
      importSuccess.value = `Imported ${data.imported} units (${data.skipped} skipped).`
      await fetchUnits()
    } else if (importType.value === 'tenants_leases') {
      importSuccess.value = `Imported ${data.importedTenants} residents & ${data.importedLeases} leases (${data.skipped} skipped).`
      await Promise.all([fetchTenants(), fetchLeases(), fetchUnits()])
    } else {
      importSuccess.value = `Imported ${data.imported} receipts (${data.skipped} skipped).`
      await fetchPayments()
    }
    parsedRows.value = []
    rawCsv.value = ''
  } catch (err: any) {
    importError.value = err.message || 'Network error connecting to import service.'
  } finally {
    isImporting.value = false
  }
}
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">PORTFOLIO SETTINGS</p>
        <h1>Settings</h1>
        <p>Property details, monthly billing schedule, administrators, and data migration.</p>
      </div>

      <div class="intro-actions" style="display: flex; gap: 8px;">
        <button type="button" class="secondary-button" @click="isImportSheetOpen = true">
          <FileSpreadsheet :size="15" />
          <span>Import CSV Data</span>
        </button>
        <button type="button" class="primary-button" @click="openPropertySheet">
          <Edit2 :size="14" />
          <span>Edit Property</span>
        </button>
      </div>
    </header>

    <div v-if="savedMessage" class="auth-alert success" style="max-width: 960px;">
      <CheckCircle2 :size="16" class="auth-alert-icon" />
      <span>{{ savedMessage }}</span>
    </div>

    <div class="settings-clean-grid" style="display: grid; grid-template-columns: 1.15fr 0.85fr; gap: 22px; max-width: 1020px; align-items: start;">
      <!-- CARD 1: Property & Billing Overview (Read-Only Display) -->
      <section class="panel" style="padding: 24px;">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 18px;">
          <div style="display: flex; align-items: center; gap: 8px;">
            <Building2 :size="18" style="color: #2563eb;" />
            <h2 style="font-size: 1.05rem; margin: 0;">Property &amp; Billing</h2>
          </div>
          <button type="button" class="secondary-button" style="padding: 5px 12px; font-size: 0.78rem;" @click="openPropertySheet">
            <Edit2 :size="13" />
            <span>Edit</span>
          </button>
        </div>

        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px;">
          <div>
            <small class="setting-label">Complex Name</small>
            <strong class="setting-val">{{ propertyInfo.name }}</strong>
          </div>
          <div>
            <small class="setting-label">City</small>
            <strong class="setting-val">{{ propertyInfo.city }}</strong>
          </div>
          <div style="grid-column: span 2;">
            <small class="setting-label">Address</small>
            <strong class="setting-val">{{ propertyInfo.address }}</strong>
          </div>
          <div>
            <small class="setting-label">Property Manager</small>
            <strong class="setting-val">{{ propertyInfo.managerName }}</strong>
          </div>
          <div>
            <small class="setting-label">M-Pesa Paybill</small>
            <strong class="setting-val mono">{{ propertyInfo.paybillNumber }}</strong>
          </div>
          <div>
            <small class="setting-label">Rent Due Day</small>
            <strong class="setting-val" style="display: inline-flex; align-items: center; gap: 6px; color: #059669;">
              <Calendar :size="14" /> Day {{ propertySettings.rentDueDay }} of every month
            </strong>
          </div>
          <div>
            <small class="setting-label">Grace Period</small>
            <strong class="setting-val">{{ propertySettings.gracePeriodDays }} days</strong>
          </div>
        </div>
      </section>

      <!-- CARD 2: Administrators List (Clean List Only — Edit in SideSheet) -->
      <div style="display: flex; flex-direction: column; gap: 20px;">
        <section class="panel" style="padding: 24px;">
          <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px;">
            <div style="display: flex; align-items: center; gap: 8px;">
              <Users :size="18" style="color: #2563eb;" />
              <h2 style="font-size: 1.05rem; margin: 0;">Administrators</h2>
            </div>
            <button
              v-if="admins.length < 2"
              type="button"
              class="secondary-button"
              style="padding: 5px 12px; font-size: 0.78rem;"
              @click="openEditAdminSheet(admins.length)"
            >
              Add Admin
            </button>
          </div>

          <div style="display: flex; flex-direction: column; gap: 10px;">
            <div
              v-for="(admin, idx) in admins"
              :key="admin.id || idx"
              style="display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 12px 14px; border: 1px solid #e2e8f0; border-radius: 8px; background: #fafbfc;"
            >
              <div style="min-width: 0;">
                <div style="font-weight: 700; color: #172033; font-size: 0.9rem;">{{ admin.name }}</div>
                <div style="font-size: 0.78rem; color: #64748b; overflow: hidden; text-overflow: ellipsis;">{{ admin.email }}</div>
                <div style="font-size: 0.76rem; color: #334155; margin-top: 3px; display: inline-flex; align-items: center; gap: 5px;">
                  <Smartphone :size="12" style="color: #2563eb;" />
                  <span class="mono">{{ admin.phone ? `+${admin.phone}` : 'No phone set' }}</span>
                </div>
              </div>

              <button
                type="button"
                class="secondary-button"
                style="padding: 5px 10px; font-size: 0.76rem; flex-shrink: 0;"
                @click="openEditAdminSheet(idx)"
              >
                <Edit2 :size="12" />
                <span>Edit</span>
              </button>
            </div>
          </div>
        </section>

        <!-- CARD 3: Account Security (Change Password & Sign Out All Devices) -->
        <section class="panel" style="padding: 20px 24px; display: flex; flex-direction: column; gap: 12px;">
          <div style="display: flex; align-items: center; gap: 8px;">
            <ShieldCheck :size="18" style="color: #0f172a;" />
            <strong style="font-size: 0.94rem; color: #172033;">Account Security</strong>
          </div>
          <small style="font-size: 0.78rem; color: #64748b;">
            Update your admin password or revoke active login sessions on all other devices.
          </small>
          <div style="display: flex; gap: 8px; flex-wrap: wrap;">
            <button type="button" class="secondary-button" style="font-size: 0.78rem;" @click="passwordError = ''; isPasswordSheetOpen = true">
              <KeyRound :size="13" />
              <span>Change Password</span>
            </button>
            <button type="button" class="secondary-button" style="font-size: 0.78rem; color: #b91c1c;" :disabled="isRevokingAll" @click="handleLogoutAll">
              <LogOut :size="13" />
              <span>{{ isRevokingAll ? 'Revoking...' : 'Sign Out All Devices' }}</span>
            </button>
          </div>
        </section>

        <!-- CARD 4: Data Migration Trigger Card -->
        <section class="panel" style="padding: 20px 24px; display: flex; align-items: center; justify-content: space-between; gap: 14px;">
          <div>
            <strong style="font-size: 0.92rem; color: #172033; display: block;">Historical Data Import</strong>
            <small style="font-size: 0.78rem; color: #64748b;">Import units, residents, leases, or past receipts via CSV.</small>
          </div>
          <button type="button" class="secondary-button" style="flex-shrink: 0;" @click="isImportSheetOpen = true">
            <UploadCloud :size="14" />
            <span>Open Importer</span>
          </button>
        </section>
      </div>
    </div>

    <!-- SHEET 0: Change Password -->
    <SideSheet
      :open="isPasswordSheetOpen"
      title="Change Password"
      subtitle="Updating your password revokes all other active sessions."
      width="440px"
      @close="isPasswordSheetOpen = false"
    >
      <form @submit.prevent="handleChangePassword">
        <div v-if="passwordError" class="auth-alert error">
          <AlertCircle :size="15" class="auth-alert-icon" />
          <span>{{ passwordError }}</span>
        </div>
        <div class="form-field">
          <label>Current Password</label>
          <input v-model="currentPassword" type="password" required placeholder="Enter current password" />
        </div>
        <div class="form-field">
          <label>New Password</label>
          <input v-model="newPassword" type="password" required minlength="6" placeholder="At least 6 characters" />
        </div>
        <div class="form-field">
          <label>Confirm New Password</label>
          <input v-model="confirmPassword" type="password" required minlength="6" placeholder="Re-enter new password" />
        </div>
        <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 20px; padding-top: 14px; border-top: 1px solid #eef2f6;">
          <button type="button" class="secondary-button" @click="isPasswordSheetOpen = false">Cancel</button>
          <button type="submit" class="primary-button" :disabled="isUpdatingPassword">
            <KeyRound :size="14" />
            <span>{{ isUpdatingPassword ? 'Updating...' : 'Update Password' }}</span>
          </button>
        </div>
      </form>
    </SideSheet>

    <!-- SHEET 1: Edit Property & Rent Due Date -->
    <SideSheet
      :open="isPropertySheetOpen"
      title="Edit Property & Billing"
      subtitle="Update complex information and monthly rent due schedule."
      width="500px"
      @close="isPropertySheetOpen = false"
    >
      <form @submit.prevent="handleSaveProperty">
        <div v-if="settingsError" class="auth-alert error">
          <AlertCircle :size="15" class="auth-alert-icon" />
          <span>{{ settingsError }}</span>
        </div>

        <div class="form-field">
          <label>Complex Name</label>
          <input v-model="propertyDraft.propertyName" required />
        </div>

        <div class="form-field">
          <label>Address</label>
          <input v-model="propertyDraft.address" />
        </div>

        <div class="form-row">
          <div class="form-field">
            <label>City</label>
            <input v-model="propertyDraft.city" />
          </div>
          <div class="form-field">
            <label>Total Floors</label>
            <input v-model.number="propertyDraft.totalFloors" type="number" min="1" />
          </div>
        </div>

        <div class="form-row">
          <div class="form-field">
            <label>Property Manager</label>
            <input v-model="propertyDraft.managerName" />
          </div>
          <div class="form-field">
            <label>M-Pesa Paybill</label>
            <input v-model="propertyDraft.paybillNumber" class="mono" />
          </div>
        </div>

        <div class="form-row">
          <div class="form-field">
            <label>Rent Due Day (1 – 28) *</label>
            <input v-model.number="propertyDraft.rentDueDay" type="number" min="1" max="28" required />
          </div>
          <div class="form-field">
            <label>Grace Period (Days)</label>
            <input v-model.number="propertyDraft.gracePeriodDays" type="number" min="0" max="20" />
          </div>
        </div>

        <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 22px; padding-top: 16px; border-top: 1px solid #eef2f6;">
          <button type="button" class="secondary-button" @click="isPropertySheetOpen = false">Cancel</button>
          <button type="submit" class="primary-button" :disabled="isSavingSettings">
            <Save :size="14" />
            <span>{{ isSavingSettings ? 'Saving...' : 'Save Changes' }}</span>
          </button>
        </div>
      </form>
    </SideSheet>

    <!-- SHEET 2: Edit Administrator -->
    <SideSheet
      :open="isAdminSheetOpen"
      title="Edit Administrator"
      subtitle="Update administrator name, email, and SMS OTP phone number."
      width="460px"
      @close="isAdminSheetOpen = false"
    >
      <form @submit.prevent="handleSaveAdmin">
        <div v-if="settingsError" class="auth-alert error">
          <AlertCircle :size="15" class="auth-alert-icon" />
          <span>{{ settingsError }}</span>
        </div>

        <div class="form-field">
          <label>Full Name</label>
          <input v-model="adminDraft.name" required placeholder="e.g. Stallone Odhiambo" />
        </div>

        <div class="form-field">
          <label>Email Address</label>
          <input v-model="adminDraft.email" type="email" required placeholder="admin@lapissuites.com" />
        </div>

        <div class="form-field">
          <label>Mobile Phone Number (SMS OTP &amp; Alerts)</label>
          <PhoneInput v-model="adminDraft.phone" required placeholder="712345678" />
        </div>

        <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 22px; padding-top: 16px; border-top: 1px solid #eef2f6;">
          <button type="button" class="secondary-button" @click="isAdminSheetOpen = false">Cancel</button>
          <button type="submit" class="primary-button" :disabled="isSavingSettings">
            <Save :size="14" />
            <span>{{ isSavingSettings ? 'Saving...' : 'Save Administrator' }}</span>
          </button>
        </div>
      </form>
    </SideSheet>

    <!-- SHEET 3: Historical CSV Data Import -->
    <SideSheet
      :open="isImportSheetOpen"
      title="Import CSV Data"
      subtitle="Upload or paste CSV rows for units, residents, leases, or historical receipts."
      width="560px"
      @close="isImportSheetOpen = false"
    >
      <div>
        <div style="display: flex; gap: 6px; margin-bottom: 14px;">
          <button
            type="button"
            class="secondary-button"
            style="font-size: 0.8rem; padding: 6px 10px;"
            :style="importType === 'units' ? 'background: #0f172a; color: white;' : ''"
            @click="importType = 'units'; parsedRows = []"
          >
            Units
          </button>
          <button
            type="button"
            class="secondary-button"
            style="font-size: 0.8rem; padding: 6px 10px;"
            :style="importType === 'tenants_leases' ? 'background: #0f172a; color: white;' : ''"
            @click="importType = 'tenants_leases'; parsedRows = []"
          >
            Residents &amp; Leases
          </button>
          <button
            type="button"
            class="secondary-button"
            style="font-size: 0.8rem; padding: 6px 10px;"
            :style="importType === 'transactions' ? 'background: #0f172a; color: white;' : ''"
            @click="importType = 'transactions'; parsedRows = []"
          >
            Past Receipts
          </button>
        </div>

        <div style="display: flex; gap: 10px; margin-bottom: 10px; align-items: center;">
          <button type="button" class="text-button" style="font-size: 0.78rem; gap: 4px; display: inline-flex; align-items: center;" @click="handleCopyTemplate">
            <component :is="copiedTemplate ? Check : Copy" :size="13" />
            {{ copiedTemplate ? 'Copied!' : 'Copy Sample CSV' }}
          </button>
          <button type="button" class="text-button" style="font-size: 0.78rem;" @click="handlePasteTemplate">
            Paste Sample
          </button>
          <label class="text-button" style="font-size: 0.78rem; cursor: pointer; margin-left: auto;">
            Upload CSV File
            <input type="file" accept=".csv,.txt" style="display: none;" @change="handleFileUpload" />
          </label>
        </div>

        <div class="form-field">
          <textarea
            v-model="rawCsv"
            rows="6"
            placeholder="Paste CSV text with column headers here..."
            class="mono"
            style="font-size: 0.78rem; line-height: 1.4; resize: vertical;"
          ></textarea>
        </div>

        <div v-if="importError" class="auth-alert error">
          <AlertCircle :size="15" class="auth-alert-icon" />
          <span>{{ importError }}</span>
        </div>

        <div v-if="importSuccess" class="auth-alert success">
          <CheckCircle2 :size="15" class="auth-alert-icon" />
          <span>{{ importSuccess }}</span>
        </div>

        <div v-if="parsedRows.length > 0" style="margin-bottom: 14px; max-height: 180px; overflow-y: auto; border: 1px solid #e2e8f0; border-radius: 6px; padding: 8px;">
          <div style="font-size: 0.75rem; font-weight: 700; color: #475569; margin-bottom: 6px;">
            Preview ({{ parsedRows.length }} rows)
          </div>
          <table style="width: 100%; border-collapse: collapse; font-size: 0.74rem;">
            <thead>
              <tr style="border-bottom: 1px solid #cbd5e1; background: #f8fafc;">
                <th v-for="(_, k) in parsedRows[0]" :key="k" style="padding: 4px 6px; text-align: left;">{{ k }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(row, idx) in parsedRows.slice(0, 5)" :key="idx" style="border-bottom: 1px solid #f1f5f9;">
                <td v-for="(val, key) in row" :key="key" style="padding: 4px 6px;">{{ val }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div style="display: flex; justify-content: flex-end; gap: 8px; padding-top: 14px; border-top: 1px solid #eef2f6;">
          <button type="button" class="secondary-button" @click="handleParseCsv">Validate &amp; Preview</button>
          <button
            v-if="parsedRows.length > 0"
            type="button"
            class="primary-button"
            :disabled="isImporting"
            @click="handleExecuteImport"
          >
            <UploadCloud :size="15" />
            <span>{{ isImporting ? 'Importing...' : `Import ${parsedRows.length} Rows` }}</span>
          </button>
        </div>
      </div>
    </SideSheet>
  </div>
</template>

<style scoped>
.setting-label {
  display: block;
  font-size: 0.72rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: #64748b;
  margin-bottom: 3px;
}

.setting-val {
  display: block;
  font-size: 0.92rem;
  color: #172033;
}

@media (max-width: 900px) {
  .settings-clean-grid {
    grid-template-columns: 1fr !important;
  }
}
</style>
