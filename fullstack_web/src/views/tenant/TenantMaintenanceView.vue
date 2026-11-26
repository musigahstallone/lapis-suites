<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import {
  Wrench,
  Plus,
  Clock,
  CheckCircle2,
  AlertTriangle,
  ArrowLeft,
  Calendar,
  Building2,
  ChevronRight
} from 'lucide-vue-next'
import { store, submitMaintenanceRequest, formatHumanDate, formatHumanDateTime, fetchMaintenance } from '../../data'
import SideSheet from '../../components/SideSheet.vue'
import type { MaintenanceCategory, MaintenancePriority, MaintenanceRequest } from '../../types'

onMounted(async () => {
  await fetchMaintenance()
})

const resident = computed(() => {
  return (
    store.tenants.find(t => store.session.email && t.email && t.email.toLowerCase() === store.session.email.toLowerCase()) ||
    store.tenants.find(t => store.session.tenantId && t.id === store.session.tenantId) ||
    store.tenants.find(t => store.session.id && t.id === store.session.id) ||
    null
  )
})

const currentUnit = computed(() => {
  if (!resident.value) return null
  return store.units.find(u => u.id === resident.value?.currentUnitId)
})

const requests = computed(() => {
  if (!resident.value) return []
  return store.maintenanceRequests.filter(m => m.tenantId === resident.value?.id)
})

// New Request Sheet
const isCreateOpen = ref(false)
const isSubmitting = ref(false)
const createError = ref('')

const form = ref({
  category: 'plumbing' as MaintenanceCategory,
  priority: 'medium' as MaintenancePriority,
  title: '',
  description: ''
})

// Details Sheet
const selectedTicket = ref<MaintenanceRequest | null>(null)
const isDetailsOpen = ref(false)

const CATEGORY_LABELS: Record<string, string> = {
  plumbing: 'Plumbing & Water',
  electrical: 'Electrical & Lighting',
  hvac: 'HVAC & Air Conditioning',
  appliance: 'Appliances & Fixtures',
  carpentry: 'Carpentry & Cabinetry',
  internet: 'Internet & Intercom',
  general: 'General Facilities'
}

function formatStatusLabel(status?: string): string {
  if (!status) return 'Pending'
  return status
    .split('_')
    .map(w => (w ? w.charAt(0).toUpperCase() + w.slice(1).toLowerCase() : ''))
    .join(' ')
}

function formatCategoryLabel(category?: string): string {
  if (!category) return 'General'
  const key = category.toLowerCase()
  return CATEGORY_LABELS[key] || key.charAt(0).toUpperCase() + key.slice(1)
}

function formatPriorityLabel(priority?: string): string {
  if (!priority) return 'Medium'
  return priority.charAt(0).toUpperCase() + priority.slice(1).toLowerCase()
}

function viewTicket(t: MaintenanceRequest) {
  selectedTicket.value = t
  isDetailsOpen.value = true
}

async function handleCreateTicket() {
  if (!form.value.title.trim() || !form.value.description.trim()) {
    createError.value = 'Please provide both a title and description.'
    return
  }

  isSubmitting.value = true
  createError.value = ''

  try {
    await submitMaintenanceRequest({
      category: form.value.category,
      priority: form.value.priority,
      title: form.value.title.trim(),
      description: form.value.description.trim(),
      unitId: currentUnit.value?.id,
      unitNumber: currentUnit.value?.unitNumber || resident.value?.currentUnitNumber || ''
    })

    form.value = {
      category: 'plumbing',
      priority: 'medium',
      title: '',
      description: ''
    }
    isCreateOpen.value = false
  } catch (err: any) {
    createError.value = err.message || 'Failed to submit maintenance request.'
  } finally {
    isSubmitting.value = false
  }
}
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">RESIDENT SERVICES</p>
        <h1>Maintenance Requests</h1>
        <p>Report issues in Unit {{ currentUnit?.unitNumber || resident?.currentUnitNumber }} and track real-time
          repairs.</p>
      </div>

      <div class="intro-actions">
        <button class="primary-button" @click="isCreateOpen = true">
          <Plus :size="15" />
          <span>New Request</span>
        </button>
      </div>
    </header>

    <!-- Tickets List Panel -->
    <section class="structured-panel">
      <div class="panel-header-bar">
        <div class="panel-header-title">
          <h2>My Service Tickets ({{ requests.length }})</h2>
          <p>Chronological status of maintenance and facility repair requests.</p>
        </div>
      </div>

      <div v-if="requests.length === 0" style="padding: 48px; text-align: center; color: #64748b;">
        <Wrench :size="32" style="margin: 0 auto 12px; color: #94a3b8;" />
        <strong style="display: block; font-size: 1rem; color: #1e293b; margin-bottom: 4px;">No active maintenance
          tickets</strong>
        <p style="font-size: 0.85rem; margin-bottom: 16px;">Everything is running smoothly. Submit a ticket if you need
          any repair or assistance.</p>
        <button class="secondary-button" @click="isCreateOpen = true">
          <Plus :size="14" /> Submit Maintenance Request
        </button>
      </div>

      <div v-else class="list-group">
        <div v-for="t in requests" :key="t.id" class="list-group-row interactive-row"
          style="cursor: pointer; padding: 16px 20px;" @click="viewTicket(t)">
          <div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; width: 100%;">
            <div style="display: flex; gap: 14px; align-items: flex-start;">
              <div
                style="width: 40px; height: 40px; border-radius: 8px; background: #f1f5f9; display: flex; align-items: center; justify-content: center; color: #334155; flex-shrink: 0;">
                <Wrench :size="18" />
              </div>
              <div>
                <div style="display: flex; align-items: center; gap: 8px; flex-wrap: wrap;">
                  <strong style="color: #0f172a; font-size: 0.94rem;">{{ t.title }}</strong>
                  <span
                    :class="['badge', t.status === 'resolved' ? 'paid' : t.status === 'in_progress' ? 'active' : 'overdue']"
                    style="font-size: 0.72rem;">
                    ● {{ formatStatusLabel(t.status) }}
                  </span>
                  <span class="badge vacant" style="font-size: 0.70rem;">
                    {{ formatPriorityLabel(t.priority) }}
                  </span>
                </div>
                <p style="font-size: 0.83rem; color: #64748b; margin: 4px 0 6px; line-clamp: 2;">
                  {{ t.description }}
                </p>
                <div style="display: flex; gap: 12px; font-size: 0.76rem; color: #94a3b8; align-items: center;">
                  <span>Logged {{ formatHumanDate(t.createdAt) }}</span>
                  <span v-if="t.assignedTo" style="color: #475467;">· Assigned to: {{ t.assignedTo }}</span>
                </div>
              </div>
            </div>

            <div style="flex-shrink: 0; align-self: center;">
              <ChevronRight :size="16" style="color: #94a3b8;" />
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Side Sheet: Submit New Maintenance Request -->
    <SideSheet :open="isCreateOpen" title="Submit Maintenance Request"
      subtitle="Report an issue in your unit for engineering dispatch" @close="isCreateOpen = false">
      <form style="display: flex; flex-direction: column; gap: 18px;" @submit.prevent="handleCreateTicket">
        <div v-if="createError"
          style="padding: 10px 12px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.82rem;">
          {{ createError }}
        </div>

        <div class="form-field">
          <label>Unit</label>
          <input :value="`Unit ${currentUnit?.unitNumber || resident?.currentUnitNumber || 'Assigned Unit'}`" readonly
            style="background: #f8fafc; color: #475467;" />
        </div>

        <div class="form-field">
          <label>Category</label>
          <select v-model="form.category" required>
            <option value="plumbing">Plumbing & Water</option>
            <option value="electrical">Electrical & Lighting</option>
            <option value="hvac">HVAC & Air Conditioning</option>
            <option value="appliance">Appliances & Fixtures</option>
            <option value="carpentry">Carpentry & Cabinetry</option>
            <option value="internet">Internet & Intercom</option>
            <option value="general">General Facilities</option>
          </select>
        </div>

        <div class="form-field">
          <label>Urgency / Priority</label>
          <select v-model="form.priority" required>
            <option value="low">Low - Routine observation</option>
            <option value="medium">Medium - Normal service</option>
            <option value="high">High - Prompt attention needed</option>
            <option value="emergency">Emergency - Water leak / Electrical hazard</option>
          </select>
        </div>

        <div class="form-field">
          <label>Issue Title</label>
          <input v-model="form.title" required placeholder="e.g. Master bathroom sink drain sluggish" />
        </div>

        <div class="form-field">
          <label>Detailed Description</label>
          <textarea v-model="form.description" required rows="4"
            placeholder="Describe what is happening, where the issue is located, and any specific details..."></textarea>
        </div>

        <div
          style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 20px; padding-top: 16px; border-top: 1px solid #eef2f6;">
          <button type="button" class="secondary-button" @click="isCreateOpen = false">
            Cancel
          </button>
          <button type="submit" class="primary-button" :disabled="isSubmitting">
            <Plus :size="15" />
            <span>{{ isSubmitting ? 'Submitting...' : 'Submit Request' }}</span>
          </button>
        </div>
      </form>
    </SideSheet>

    <!-- Side Sheet: Ticket Details -->
    <SideSheet :open="isDetailsOpen" :title="selectedTicket?.title || 'Ticket Details'"
      :subtitle="`Ticket Ref #${selectedTicket?.id?.slice(-6).toUpperCase()} · Unit ${selectedTicket?.unitNumber}`"
      @close="isDetailsOpen = false">
      <div v-if="selectedTicket" class="tenant-ticket-detail">
        <!-- Status & Priority Row -->
        <div class="detail-badges-row">
          <span
            :class="['badge', selectedTicket.status === 'resolved' ? 'paid' : selectedTicket.status === 'in_progress' ? 'active' : 'overdue']">
            ● {{ formatStatusLabel(selectedTicket.status) }}
          </span>
          <span :class="['badge', selectedTicket.priority === 'emergency' ? 'overdue' : 'vacant']">
            {{ formatPriorityLabel(selectedTicket.priority) }} Priority
          </span>
        </div>

        <!-- Issue Description Card -->
        <div class="detail-section-card">
          <span class="detail-section-label">Issue Description</span>
          <p class="detail-description-text">{{ selectedTicket.description }}</p>
        </div>

        <!-- Metadata Grid -->
        <div class="detail-meta-grid">
          <div class="detail-meta-card">
            <span class="detail-meta-label">Category</span>
            <strong class="detail-meta-value">{{ formatCategoryLabel(selectedTicket.category) }}</strong>
          </div>
          <div class="detail-meta-card">
            <span class="detail-meta-label">Reported On</span>
            <strong class="detail-meta-value">{{ formatHumanDate(selectedTicket.createdAt) }}</strong>
          </div>
          <div class="detail-meta-card detail-meta-full">
            <span class="detail-meta-label">Assigned Technician / Vendor</span>
            <strong class="detail-meta-value" :class="{ 'is-muted': !selectedTicket.assignedTo }">
              {{ selectedTicket.assignedTo || 'Pending assignment' }}
            </strong>
          </div>
        </div>

        <!-- Management Update / Resolution Notes -->
        <div
          v-if="selectedTicket.resolutionNotes"
          :class="['detail-resolution-card', selectedTicket.status === 'resolved' ? 'is-resolved' : 'is-update']"
        >
          <span class="detail-section-label">
            {{ selectedTicket.status === 'resolved' ? 'Resolution Notes' : 'Latest Update from Management' }}
          </span>
          <p class="detail-resolution-text">{{ selectedTicket.resolutionNotes }}</p>
          <small v-if="selectedTicket.resolvedAt" class="detail-resolution-time">
            Completed {{ formatHumanDateTime(selectedTicket.resolvedAt) }}
          </small>
        </div>
      </div>
    </SideSheet>
  </div>
</template>

<style scoped>
.tenant-ticket-detail {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.detail-badges-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  flex-wrap: wrap;
}

.detail-section-card {
  padding: 15px 16px;
  background: #f8fafc;
  border: 1px solid #e2e8f0;
  border-radius: 10px;
}

.detail-section-label {
  display: block;
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #64748b;
  margin-bottom: 6px;
}

.detail-description-text {
  margin: 0;
  font-size: 0.88rem;
  color: #334155;
  line-height: 1.55;
}

.detail-meta-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.detail-meta-card {
  padding: 12px 14px;
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.detail-meta-full {
  grid-column: span 2;
}

.detail-meta-label {
  font-size: 0.72rem;
  font-weight: 600;
  color: #64748b;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.detail-meta-value {
  font-size: 0.88rem;
  font-weight: 600;
  color: #0f172a;
}

.detail-meta-value.is-muted {
  color: #64748b;
  font-weight: 500;
}

.detail-resolution-card {
  padding: 15px 16px;
  border-radius: 10px;
  border: 1px solid #bfdbfe;
  background: #eff6ff;
}

.detail-resolution-card.is-resolved {
  background: #f0fdf4;
  border-color: #bbf7d0;
}

.detail-resolution-card.is-resolved .detail-section-label {
  color: #15803d;
}

.detail-resolution-card.is-update .detail-section-label {
  color: #1d4ed8;
}

.detail-resolution-text {
  margin: 0;
  font-size: 0.87rem;
  line-height: 1.5;
  color: #1e293b;
}

.detail-resolution-time {
  display: block;
  margin-top: 8px;
  font-size: 0.74rem;
  color: #64748b;
}

@media (max-width: 480px) {
  .detail-meta-grid {
    grid-template-columns: 1fr;
  }
  .detail-meta-full {
    grid-column: span 1;
  }
}
</style>
