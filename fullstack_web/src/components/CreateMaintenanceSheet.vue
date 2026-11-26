<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { Send } from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import SearchableSelect from './SearchableSelect.vue'
import { store, createMaintenanceRequest } from '../data'
import type { MaintenanceCategory, MaintenancePriority } from '../types'

const props = defineProps<{
  open: boolean
  defaultTenantId?: string
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'created'): void
}>()

const isLandlord = computed(() => store.session.role === 'landlord')

const selectedTenantId = ref(props.defaultTenantId || '')
const category = ref<MaintenanceCategory>('plumbing')
const priority = ref<MaintenancePriority>('medium')
const title = ref('')
const description = ref('')
const isSubmitting = ref(false)
const error = ref('')

const tenantSelectOptions = computed(() => {
  return store.tenants.map(t => ({
    value: t.id,
    label: `${t.name}${t.currentUnitNumber ? ` — Unit ${t.currentUnitNumber}` : ''}`,
    sublabel: t.phone || t.email
  }))
})

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      error.value = ''
      if (props.defaultTenantId) {
        selectedTenantId.value = props.defaultTenantId
      } else if (isLandlord.value && !selectedTenantId.value && store.tenants.length > 0) {
        selectedTenantId.value = store.tenants[0].id
      }
    }
  }
)

const currentTenant = computed(() => {
  if (isLandlord.value) {
    return store.tenants.find(t => t.id === selectedTenantId.value) || null
  }
  if (props.defaultTenantId) {
    return store.tenants.find(t => t.id === props.defaultTenantId)
  }
  return (
    store.tenants.find(t => t.id === store.session.tenantId || t.id === store.session.id) ||
    store.tenants.find(t => t.email.toLowerCase() === store.session.email.toLowerCase()) ||
    store.tenants[0]
  )
})

async function handleSubmit() {
  if (!currentTenant.value) {
    error.value = isLandlord.value ? 'Please select a resident / unit.' : 'Resident profile not identified.'
    return
  }
  if (!title.value.trim()) {
    error.value = 'Please provide a brief title of the issue.'
    return
  }
  if (!description.value.trim()) {
    error.value = 'Please provide descriptive details of the required repair.'
    return
  }

  isSubmitting.value = true
  error.value = ''

  try {
    await createMaintenanceRequest({
      tenantId: currentTenant.value.id,
      unitId: currentTenant.value.currentUnitId || undefined,
      unitNumber: currentTenant.value.currentUnitNumber || '',
      category: category.value,
      priority: priority.value,
      title: title.value.trim(),
      description: description.value.trim()
    } as any)

    title.value = ''
    description.value = ''
    category.value = 'plumbing'
    priority.value = 'medium'

    emit('created')
    emit('close')
  } catch (e: any) {
    error.value = e?.message || 'Failed to submit maintenance request.'
  } finally {
    isSubmitting.value = false
  }
}
</script>

<template>
  <SideSheet
    :open="open"
    :title="isLandlord ? 'Create Maintenance Ticket' : 'Request Maintenance'"
    :subtitle="isLandlord ? 'Log a facility ticket for a unit and notify the resident via SMS.' : 'Submit a repair or service request directly to the facilities team.'"
    @close="emit('close')"
  >
    <form @submit.prevent="handleSubmit" class="maintenance-create-form">
      <div v-if="error" class="auth-alert error" style="margin-bottom: 16px;">
        <span>{{ error }}</span>
      </div>

      <!-- Landlord: Choose Resident / Unit -->
      <div v-if="isLandlord" class="form-field" style="margin-bottom: 16px;">
        <label>Resident &amp; Unit *</label>
        <SearchableSelect
          v-model="selectedTenantId"
          :options="tenantSelectOptions"
          placeholder="Select resident or unit..."
          search-placeholder="Search by resident name or unit..."
        />
      </div>

      <!-- Resident: Auto Unit Pill -->
      <div v-else class="panel" style="padding: 14px 16px; margin-bottom: 18px; background: #f8fafc; border: 1px solid #e2e8f0; display: flex; align-items: center; justify-content: space-between;">
        <div>
          <span style="font-size: 0.72rem; text-transform: uppercase; color: #64748b; font-weight: 700;">Location</span>
          <div style="font-size: 0.95rem; font-weight: 700; color: #172033; margin-top: 2px;">
            Unit {{ currentTenant?.currentUnitNumber || 'Suite' }} — Lapis Suites
          </div>
        </div>
        <span class="badge active" style="font-size: 0.75rem;">{{ currentTenant?.name }}</span>
      </div>

      <div class="form-row">
        <div class="form-field">
          <label>Issue Category *</label>
          <select v-model="category" required>
            <option value="plumbing">Plumbing &amp; Sanitary</option>
            <option value="electrical">Electrical &amp; Lighting</option>
            <option value="hvac">HVAC &amp; Air Conditioning</option>
            <option value="appliance">Kitchen / Built-in Appliances</option>
            <option value="carpentry">Doors, Locks &amp; Joinery</option>
            <option value="internet">Access Control &amp; Intercom</option>
            <option value="general">General Facility Maintenance</option>
          </select>
        </div>

        <div class="form-field">
          <label>Urgency Level *</label>
          <select v-model="priority" required>
            <option value="low">Low — Routine check</option>
            <option value="medium">Medium — Standard service</option>
            <option value="high">High — Prompt attention</option>
            <option value="emergency">Emergency — Immediate hazard</option>
          </select>
        </div>
      </div>

      <div class="form-field">
        <label>Issue Summary *</label>
        <input v-model="title" required placeholder="e.g. Kitchen sink tap leaking" />
      </div>

      <div class="form-field">
        <label>Detailed Description *</label>
        <textarea v-model="description" rows="4" required placeholder="Describe the issue and any instructions..."></textarea>
      </div>

      <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 24px; padding-top: 18px; border-top: 1px solid #e2e8f0;">
        <button type="button" class="secondary-button" @click="emit('close')">Cancel</button>
        <button type="submit" class="primary-button" :disabled="isSubmitting">
          <Send :size="15" />
          <span>{{ isSubmitting ? 'Submitting...' : isLandlord ? 'Create Ticket & Notify Resident' : 'Submit Request' }}</span>
        </button>
      </div>
    </form>
  </SideSheet>
</template>

<style scoped>
.maintenance-create-form {
  padding: 4px 0;
}
</style>
