<script setup lang="ts">
import { ref, watch } from 'vue'
import {
  Wrench,
  Clock,
  CheckCircle2,
  AlertTriangle,
  UserCheck,
  FileText,
  Save,
  Tag
} from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import { updateMaintenanceRequest, formatHumanDateTime } from '../data'
import type { MaintenanceRequest, MaintenanceStatus } from '../types'

const props = defineProps<{
  open: boolean
  request: MaintenanceRequest | null
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'updated'): void
}>()

const status = ref<MaintenanceStatus>('pending')
const assignedTo = ref('')
const resolutionNotes = ref('')
const isSaving = ref(false)
const error = ref('')

watch(
  () => props.request,
  (req) => {
    if (req) {
      status.value = req.status
      assignedTo.value = req.assignedTo || ''
      resolutionNotes.value = req.resolutionNotes || ''
      error.value = ''
    }
  },
  { immediate: true }
)

const CATEGORY_LABELS: Record<string, string> = {
  plumbing: 'Plumbing & Water',
  electrical: 'Electrical & Lighting',
  hvac: 'HVAC & Air Conditioning',
  appliance: 'Appliances & Fixtures',
  carpentry: 'Carpentry & Cabinetry',
  internet: 'Internet & Intercom',
  general: 'General Facilities'
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

const quickTemplates: { label: string; status: MaintenanceStatus; text: string }[] = [
  {
    label: 'Technician Dispatched',
    status: 'in_progress',
    text: 'A technician has been dispatched to your unit to inspect and resolve this issue. Kindly ensure access to the suite.'
  },
  {
    label: 'Inspection Scheduled',
    status: 'in_progress',
    text: 'Our maintenance team has reviewed your ticket and scheduled a quick inspection to assess the repair scope.'
  },
  {
    label: 'Parts Ordered',
    status: 'in_progress',
    text: 'Replacement parts have been ordered for this repair. We will notify you as soon as installation is scheduled.'
  },
  {
    label: 'Access Needed',
    status: 'in_progress',
    text: 'Our technician attempted to reach you regarding this repair. Kindly contact management to arrange unit access.'
  },
  {
    label: 'Issue Resolved',
    status: 'resolved',
    text: 'The reported maintenance issue has been repaired and verified. Please let us know if anything further is needed.'
  }
]

function applyTemplate(tpl: { status: MaintenanceStatus; text: string }) {
  status.value = tpl.status
  resolutionNotes.value = tpl.text
}

function handleSave() {
  if (!props.request) return
  isSaving.value = true
  error.value = ''

  try {
    updateMaintenanceRequest(props.request.id, {
      status: status.value,
      assignedTo: assignedTo.value,
      resolutionNotes: resolutionNotes.value
    })
    emit('updated')
    emit('close')
  } catch (e: any) {
    error.value = e?.message || 'Failed to update ticket.'
  } finally {
    isSaving.value = false
  }
}
</script>

<template>
  <SideSheet
    :open="open"
    :title="`Work Order #${request?.id?.slice(-6)?.toUpperCase() || 'DETAILS'}`"
    subtitle="Inspect, dispatch technician, and record resolution."
    @close="emit('close')"
  >
    <div v-if="request" class="maintenance-sheet-content">
      <!-- Error Message -->
      <div v-if="error" class="error-banner" style="margin-bottom: 16px;">
        {{ error }}
      </div>

      <!-- Ticket Header Summary -->
      <div class="panel" style="padding: 16px; margin-bottom: 18px; background: #f8fafc; border: 1px solid #e2e8f0;">
        <div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; margin-bottom: 10px;">
          <div>
            <span style="font-size: 0.72rem; text-transform: uppercase; color: #64748b; font-weight: 700; letter-spacing: 0.5px;">
              Unit {{ request.unitNumber }} · Reported by {{ request.tenantName }}
            </span>
            <h2 style="font-size: 1.05rem; margin: 4px 0 0; color: #172033; font-weight: 700;">
              {{ request.title }}
            </h2>
          </div>
          <span :class="['badge', `priority-${request.priority}`]">
            {{ formatPriorityLabel(request.priority) }} Priority
          </span>
        </div>

        <p style="font-size: 0.88rem; color: #475569; margin: 0; line-height: 1.45;">
          {{ request.description }}
        </p>

        <div style="display: flex; gap: 16px; flex-wrap: wrap; margin-top: 12px; padding-top: 10px; border-top: 1px solid #e2e8f0; font-size: 0.75rem; color: #64748b;">
          <span>Category: <strong style="color: #172033;">{{ formatCategoryLabel(request.category) }}</strong></span>
          <span>Logged: <strong style="color: #172033;">{{ formatHumanDateTime(request.createdAt) }}</strong></span>
        </div>
      </div>

      <!-- Locked Read-Only State if Resolved -->
      <div v-if="request.status === 'resolved'" style="display: flex; flex-direction: column; gap: 14px;">
        <div style="padding: 14px 16px; background: #ecfdf5; border: 1px solid #a7f3d0; border-radius: 10px; color: #065f46; font-size: 0.84rem;">
          <strong style="display: block; margin-bottom: 3px;">✓ Resolved &amp; Locked</strong>
          Completed tickets cannot be edited or reopened.
        </div>
        <div v-if="request.assignedTo" style="font-size: 0.84rem; color: #334155;">
          Technician: <strong>{{ request.assignedTo }}</strong>
        </div>
        <div v-if="request.resolutionNotes" style="font-size: 0.84rem; color: #334155;">
          Notes: {{ request.resolutionNotes }}
        </div>
        <div style="display: flex; justify-content: flex-end; padding-top: 10px;">
          <button type="button" class="secondary-button" @click="emit('close')">Close</button>
        </div>
      </div>

      <!-- Work Order Form Controls -->
      <form v-else @submit.prevent="handleSave">
        <div class="form-field">
          <label>Work Order Status *</label>
          <select v-model="status" required>
            <option value="pending">Pending Review / Triage</option>
            <option value="in_progress">In Progress / Assigned</option>
            <option value="resolved">Resolved / Completed</option>
            <option value="cancelled">Cancelled / Void</option>
          </select>
        </div>

        <div class="form-field">
          <label>Assigned Technician / Contractor</label>
          <input
            v-model="assignedTo"
            placeholder="e.g. Kamau Plumbing Solutions (+254 712 345 678)"
          />
          <small style="color: #64748b; font-size: 0.74rem; margin-top: 4px;">
            Service provider or in-house maintenance engineer dispatched.
          </small>
        </div>

        <div class="form-field">
          <label style="margin-bottom: 6px;">Quick Message Templates</label>
          <div class="sheet-tpl-row">
            <button
              v-for="tpl in quickTemplates"
              :key="tpl.label"
              type="button"
              class="sheet-tpl-chip"
              :class="{ active: resolutionNotes === tpl.text }"
              @click="applyTemplate(tpl)"
            >
              {{ tpl.label }}
            </button>
          </div>
        </div>

        <div class="form-field">
          <label>Resolution &amp; Service Notes</label>
          <textarea
            v-model="resolutionNotes"
            rows="4"
            placeholder="Details of repair work performed, replacement parts, and resident update..."
          ></textarea>
        </div>

        <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 24px; padding-top: 18px; border-top: 1px solid #e2e8f0;">
          <button
            type="button"
            class="secondary-button"
            @click="emit('close')"
          >
            Cancel
          </button>
          <button
            type="submit"
            class="primary-button"
            :disabled="isSaving"
          >
            <Save :size="15" />
            <span>{{ isSaving ? 'Saving...' : 'Update Work Order' }}</span>
          </button>
        </div>
      </form>
    </div>
  </SideSheet>
</template>

<style scoped>
.maintenance-sheet-content {
  padding: 4px 0;
}

.sheet-tpl-row {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.sheet-tpl-chip {
  padding: 4px 10px;
  font-size: 0.74rem;
  font-weight: 600;
  color: #334155;
  background: #f8fafc;
  border: 1px solid #cbd5e1;
  border-radius: 999px;
  cursor: pointer;
  font-family: inherit;
  transition: all 0.14s ease;
}

.sheet-tpl-chip:hover {
  background: #eff6ff;
  border-color: #93c5fd;
  color: #1d4ed8;
}

.sheet-tpl-chip.active {
  background: #0f172a;
  border-color: #0f172a;
  color: #ffffff;
}
</style>
