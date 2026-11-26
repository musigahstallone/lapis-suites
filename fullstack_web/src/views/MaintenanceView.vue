<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import {
  Wrench,
  Search,
  CheckCircle2,
  Clock,
  AlertTriangle,
  ChevronRight,
  Filter,
  UserCheck,
  Building2,
  Plus
} from 'lucide-vue-next'
import { store, updateMaintenanceStatus, formatHumanDate, formatHumanDateTime, fetchMaintenance, fetchTenants } from '../data'
import SideSheet from '../components/SideSheet.vue'
import CreateMaintenanceSheet from '../components/CreateMaintenanceSheet.vue'
import PaginationControl from '../components/PaginationControl.vue'
import type { MaintenanceRequest, MaintenanceStatus, MaintenancePriority } from '../types'

const activeTab = ref<'all' | 'pending' | 'in_progress' | 'resolved'>('all')
const searchQuery = ref('')

// Pagination
const currentPage = ref(1)
const pageSize = ref(10)

// Ticket Edit Side Sheet
const isCreateOpen = ref(false)
const selectedTicket = ref<MaintenanceRequest | null>(null)
const isEditOpen = ref(false)
const isSaving = ref(false)
const saveError = ref('')

const editForm = ref({
  status: 'pending' as MaintenanceStatus,
  assignedTo: '',
  resolutionNotes: ''
})

const CATEGORY_LABELS: Record<string, string> = {
  plumbing: 'Plumbing',
  electrical: 'Electrical',
  hvac: 'HVAC',
  appliance: 'Appliance',
  carpentry: 'Carpentry',
  internet: 'Internet',
  general: 'General'
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

const messageTemplates: { id: string; label: string; status: MaintenanceStatus; text: string }[] = [
  {
    id: 'dispatched',
    label: 'Technician Dispatched',
    status: 'in_progress',
    text: 'A technician has been dispatched to your unit to inspect and resolve this issue. Kindly ensure access to the suite.'
  },
  {
    id: 'inspection',
    label: 'Inspection Scheduled',
    status: 'in_progress',
    text: 'Our maintenance team has reviewed your ticket and scheduled a quick inspection shortly to assess the repair scope.'
  },
  {
    id: 'parts',
    label: 'Parts Ordered',
    status: 'in_progress',
    text: 'Replacement parts have been ordered for this repair. We will notify you as soon as installation is scheduled.'
  },
  {
    id: 'access',
    label: 'Unit Access Needed',
    status: 'in_progress',
    text: 'Our technician attempted to reach you regarding this repair. Kindly contact management to arrange convenient unit access.'
  },
  {
    id: 'resolved',
    label: 'Issue Resolved',
    status: 'resolved',
    text: 'The reported maintenance issue has been repaired and verified. Please let us know if anything further is needed.'
  },
  {
    id: 'verified_normal',
    label: 'Checked & Normal',
    status: 'cancelled',
    text: 'We inspected the reported issue and confirmed everything is operating normally. Feel free to log a new ticket if it recurs.'
  }
]

function applyMessageTemplate(tpl: { status: MaintenanceStatus; text: string }) {
  editForm.value.status = tpl.status
  editForm.value.resolutionNotes = tpl.text
}

onMounted(async () => {
  await Promise.all([fetchMaintenance(), fetchTenants()])
})

const filteredTickets = computed(() => {
  return store.maintenanceRequests.filter(m => {
    const matchesTab = activeTab.value === 'all' || m.status === activeTab.value
    const q = searchQuery.value.trim().toLowerCase()
    const matchesSearch =
      !q ||
      m.title.toLowerCase().includes(q) ||
      m.description.toLowerCase().includes(q) ||
      m.unitNumber.toLowerCase().includes(q) ||
      m.tenantName.toLowerCase().includes(q) ||
      m.category.toLowerCase().includes(q)

    return matchesTab && matchesSearch
  })
})

const paginatedTickets = computed(() => {
  const start = (currentPage.value - 1) * pageSize.value
  return filteredTickets.value.slice(start, start + pageSize.value)
})

// Metrics
const metrics = computed(() => {
  const total = store.maintenanceRequests.length
  const pending = store.maintenanceRequests.filter(m => m.status === 'pending').length
  const inProgress = store.maintenanceRequests.filter(m => m.status === 'in_progress').length
  const resolved = store.maintenanceRequests.filter(m => m.status === 'resolved').length
  return { total, pending, inProgress, resolved }
})

function openEditSheet(ticket: MaintenanceRequest) {
  selectedTicket.value = ticket
  editForm.value = {
    status: ticket.status,
    assignedTo: ticket.assignedTo || '',
    resolutionNotes: ticket.resolutionNotes || ''
  }
  saveError.value = ''
  isEditOpen.value = true
}

async function handleSaveStatus() {
  if (!selectedTicket.value) return
  isSaving.value = true
  saveError.value = ''

  try {
    await updateMaintenanceStatus(selectedTicket.value.id, {
      status: editForm.value.status,
      assignedTo: editForm.value.assignedTo.trim() || undefined,
      resolutionNotes: editForm.value.resolutionNotes.trim() || undefined
    })
    isEditOpen.value = false
  } catch (err: any) {
    saveError.value = err.message || 'Failed to update ticket.'
  } finally {
    isSaving.value = false
  }
}
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">FACILITY OPERATIONS</p>
        <h1>Maintenance &amp; Repairs</h1>
        <p>Manage resident issue reports, create maintenance tickets, dispatch technicians, and resolve facility requests.</p>
      </div>

      <div class="intro-actions">
        <button type="button" class="primary-button" @click="isCreateOpen = true">
          <Plus :size="15" />
          <span>New Ticket</span>
        </button>
      </div>
    </header>

    <!-- Metrics Grid -->
    <section class="stats-grid" style="margin-bottom: 24px;">
      <article class="stat-card">
        <div class="stat-label">Total Requests</div>
        <div class="stat-value">{{ metrics.total }}</div>
        <div class="stat-trend neutral">
          <span>All recorded maintenance items</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Pending Action</div>
        <div class="stat-value text-danger">{{ metrics.pending }}</div>
        <div class="stat-trend negative">
          <span>Awaiting vendor / technician dispatch</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">In Progress</div>
        <div class="stat-value" style="color: #2563eb;">{{ metrics.inProgress }}</div>
        <div class="stat-trend neutral">
          <span>Currently under repair</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Resolved</div>
        <div class="stat-value text-positive">{{ metrics.resolved }}</div>
        <div class="stat-trend positive">
          <span>Completed repairs</span>
        </div>
      </article>
    </section>

    <!-- Structured Panel -->
    <section class="structured-panel">
      <!-- Header bar with tabs & search -->
      <div class="panel-header-bar" style="flex-wrap: wrap; gap: 12px;">
        <div class="filter-tabs">
          <button
            type="button"
            :class="['tab-btn', { active: activeTab === 'all' }]"
            @click="activeTab = 'all'; currentPage = 1"
          >
            All ({{ metrics.total }})
          </button>
          <button
            type="button"
            :class="['tab-btn', { active: activeTab === 'pending' }]"
            @click="activeTab = 'pending'; currentPage = 1"
          >
            Pending ({{ metrics.pending }})
          </button>
          <button
            type="button"
            :class="['tab-btn', { active: activeTab === 'in_progress' }]"
            @click="activeTab = 'in_progress'; currentPage = 1"
          >
            In Progress ({{ metrics.inProgress }})
          </button>
          <button
            type="button"
            :class="['tab-btn', { active: activeTab === 'resolved' }]"
            @click="activeTab = 'resolved'; currentPage = 1"
          >
            Resolved ({{ metrics.resolved }})
          </button>
        </div>

        <div class="page-search-bar" style="width: 240px; margin-left: auto;">
          <Search :size="15" class="search-icon" />
          <input v-model="searchQuery" placeholder="Search tickets..." @input="currentPage = 1" />
        </div>
      </div>

      <!-- Responsive Table -->
      <div class="table-responsive-wrapper">
        <div class="list-group-header hide-mobile" style="display: grid; grid-template-columns: 80px 180px 1fr 140px 130px 80px; gap: 12px; padding: 12px 18px; font-size: 0.78rem; font-weight: 600; color: #64748b; border-bottom: 1px solid #eef2f6;">
          <span>Unit</span>
          <span>Resident</span>
          <span>Issue Summary</span>
          <span>Category / Priority</span>
          <span>Status</span>
          <span style="text-align: right;">Action</span>
        </div>

        <div
          v-for="t in paginatedTickets"
          :key="t.id"
          class="list-group-row interactive-row"
          style="cursor: pointer; padding: 14px 18px;"
          @click="openEditSheet(t)"
        >
          <!-- Desktop Grid -->
          <div class="hide-mobile" style="display: grid; grid-template-columns: 80px 180px 1fr 140px 130px 80px; gap: 12px; align-items: center; width: 100%;">
            <div>
              <span class="badge occupied">Unit {{ t.unitNumber }}</span>
            </div>

            <div>
              <strong style="color: #0f172a; font-size: 0.88rem; display: block;">{{ t.tenantName }}</strong>
              <small style="color: #64748b; font-size: 0.76rem;">{{ formatHumanDate(t.createdAt) }}</small>
            </div>

            <div style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
              <strong style="color: #1e293b; font-size: 0.88rem;">{{ t.title }}</strong>
              <span style="color: #64748b; font-size: 0.80rem; margin-left: 6px;">— {{ t.description }}</span>
            </div>

            <div>
              <div style="display: flex; gap: 6px; align-items: center; flex-wrap: wrap;">
                <span class="badge vacant" style="font-size: 0.72rem;">{{ formatCategoryLabel(t.category) }}</span>
                <span :class="['badge', t.priority === 'emergency' ? 'overdue' : 'vacant']" style="font-size: 0.70rem;">
                  {{ formatPriorityLabel(t.priority) }}
                </span>
              </div>
            </div>

            <div>
              <span
                :class="['badge', t.status === 'resolved' ? 'paid' : t.status === 'in_progress' ? 'active' : 'overdue']"
                style="font-size: 0.76rem;"
              >
                ● {{ formatStatusLabel(t.status) }}
              </span>
            </div>

            <div style="text-align: right;">
              <button
                type="button"
                class="secondary-button"
                style="padding: 4px 10px; height: 30px; font-size: 0.78rem;"
                @click.stop="openEditSheet(t)"
              >
                Manage
              </button>
            </div>
          </div>

          <!-- Mobile Card -->
          <div class="show-mobile-only" style="width: 100%;">
            <div style="display: flex; justify-content: space-between; align-items: flex-start; gap: 8px; margin-bottom: 6px;">
              <div>
                <span class="badge occupied">Unit {{ t.unitNumber }}</span>
                <strong style="margin-left: 8px; color: #0f172a; font-size: 0.90rem;">{{ t.title }}</strong>
              </div>
              <span
                :class="['badge', t.status === 'resolved' ? 'paid' : t.status === 'in_progress' ? 'active' : 'overdue']"
                style="font-size: 0.72rem; flex-shrink: 0;"
              >
                ● {{ formatStatusLabel(t.status) }}
              </span>
            </div>
            <p style="font-size: 0.82rem; color: #64748b; margin: 4px 0 8px;">
              {{ t.description }}
            </p>
            <div style="display: flex; justify-content: space-between; align-items: center; font-size: 0.76rem; color: #94a3b8;">
              <span>{{ t.tenantName }} · {{ formatHumanDate(t.createdAt) }}</span>
              <span class="badge vacant">{{ formatCategoryLabel(t.category) }}</span>
            </div>
          </div>
        </div>
      </div>

      <div v-if="filteredTickets.length === 0" style="padding: 40px; text-align: center; color: #64748b;">
        No maintenance tickets match the selected criteria.
      </div>

      <PaginationControl
        v-model:current-page="currentPage"
        v-model:page-size="pageSize"
        :total-items="filteredTickets.length"
      />
    </section>

    <!-- Side Sheet: Manage Maintenance Ticket -->
    <SideSheet
      :open="isEditOpen"
      :title="`Manage Ticket #${selectedTicket?.id?.slice(-6).toUpperCase()}`"
      :subtitle="`Unit ${selectedTicket?.unitNumber} · Reported by ${selectedTicket?.tenantName}`"
      @close="isEditOpen = false"
    >
      <div v-if="selectedTicket" style="display: flex; flex-direction: column; gap: 20px;">
        <!-- Issue Summary Panel -->
        <div class="panel" style="padding: 16px; background: #f8fafc; border: 1px solid #e2e8f0;">
          <strong style="display: block; font-size: 0.92rem; color: #0f172a; margin-bottom: 4px;">{{ selectedTicket.title }}</strong>
          <p style="font-size: 0.84rem; color: #475467; line-height: 1.5;">{{ selectedTicket.description }}</p>
          <div style="margin-top: 10px; display: flex; gap: 8px; flex-wrap: wrap;">
            <span class="badge vacant">{{ formatCategoryLabel(selectedTicket.category) }}</span>
            <span class="badge vacant">{{ formatPriorityLabel(selectedTicket.priority) }} Priority</span>
            <small style="color: #94a3b8; align-self: center; font-size: 0.76rem;">Reported {{ formatHumanDateTime(selectedTicket.createdAt) }}</small>
          </div>
        </div>

        <!-- Resolved & Locked Read-Only View -->
        <div v-if="selectedTicket.status === 'resolved'" style="display: flex; flex-direction: column; gap: 14px;">
          <div style="padding: 14px 16px; background: #ecfdf5; border: 1px solid #a7f3d0; border-radius: 10px; color: #065f46;">
            <strong style="display: block; font-size: 0.88rem; margin-bottom: 4px;">✓ Resolved &amp; Locked</strong>
            <p style="margin: 0; font-size: 0.82rem; line-height: 1.45;">
              This maintenance ticket is complete and locked from further edits or reopening.
            </p>
          </div>
          <div class="panel" style="padding: 14px 16px; display: flex; flex-direction: column; gap: 8px; font-size: 0.84rem;">
            <div><span style="color: #64748b;">Assigned Technician:</span> <strong>{{ selectedTicket.assignedTo || 'Management Team' }}</strong></div>
            <div v-if="selectedTicket.resolutionNotes">
              <span style="color: #64748b; display: block; margin-bottom: 3px;">Resolution Notes:</span>
              <p style="margin: 0; color: #0f172a; line-height: 1.45;">{{ selectedTicket.resolutionNotes }}</p>
            </div>
          </div>
          <div style="display: flex; justify-content: flex-end; padding-top: 8px;">
            <button type="button" class="secondary-button" @click="isEditOpen = false">Close</button>
          </div>
        </div>

        <form v-else style="display: flex; flex-direction: column; gap: 16px;" @submit.prevent="handleSaveStatus">
          <div v-if="saveError" style="padding: 10px 12px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.82rem;">
            {{ saveError }}
          </div>

          <div class="form-field">
            <label>Ticket Status</label>
            <select v-model="editForm.status" required>
              <option value="pending">Pending - Needs triage / dispatch</option>
              <option value="in_progress">In Progress - Technician dispatched</option>
              <option value="resolved">Resolved - Work completed & verified</option>
              <option value="cancelled">Cancelled - Not applicable</option>
            </select>
          </div>

          <div class="form-field">
            <label>Assigned Technician / Vendor</label>
            <input
              v-model="editForm.assignedTo"
              placeholder="e.g. Nairobi Prime Plumbing Services / John Kamau"
            />
          </div>

          <!-- Quick Message Templates for Resident SMS & Ticket Notes -->
          <div class="form-field">
            <label style="margin-bottom: 6px;">Quick Message Templates</label>
            <div style="display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 6px;">
              <button
                v-for="tpl in messageTemplates"
                :key="tpl.id"
                type="button"
                class="tpl-chip"
                :class="{ active: editForm.resolutionNotes === tpl.text }"
                @click="applyMessageTemplate(tpl)"
              >
                {{ tpl.label }}
              </button>
            </div>
            <small style="font-size: 0.74rem; color: #64748b;">
              Tap a template to pre-fill the status and message sent to the resident via SMS.
            </small>
          </div>

          <div class="form-field">
            <label>Resident Update / Resolution Notes</label>
            <textarea
              v-model="editForm.resolutionNotes"
              rows="3"
              placeholder="Detail actions taken, dispatch updates, or instructions for the resident..."
            ></textarea>
          </div>

          <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 20px; padding-top: 16px; border-top: 1px solid #eef2f6;">
            <button type="button" class="secondary-button" @click="isEditOpen = false">
              Cancel
            </button>
            <button type="submit" class="primary-button" :disabled="isSaving">
              <CheckCircle2 :size="15" />
              <span>{{ isSaving ? 'Saving...' : 'Update & Notify Resident' }}</span>
            </button>
          </div>
        </form>
      </div>
    </SideSheet>

    <!-- Admin Create Maintenance Ticket SideSheet (Also notifies tenant via SMS) -->
    <CreateMaintenanceSheet
      :open="isCreateOpen"
      @close="isCreateOpen = false"
      @created="fetchMaintenance"
    />
  </div>
</template>

<style scoped>
.tpl-chip {
  padding: 5px 10px;
  font-size: 0.75rem;
  font-weight: 600;
  color: #334155;
  background: #f8fafc;
  border: 1px solid #cbd5e1;
  border-radius: 999px;
  cursor: pointer;
  transition: all 0.14s ease;
  font-family: inherit;
}

.tpl-chip:hover {
  background: #eff6ff;
  border-color: #93c5fd;
  color: #1d4ed8;
}

.tpl-chip.active {
  background: #0f172a;
  border-color: #0f172a;
  color: #ffffff;
}
</style>
