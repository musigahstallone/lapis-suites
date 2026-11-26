<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import {
  FileText,
  Building2,
  Calendar,
  Clock,
  Plus,
  ArrowLeft,
  CheckCircle2,
  TrendingUp,
  ShieldAlert,
  ChevronRight,
  Filter
} from 'lucide-vue-next'
import {
  store,
  formatKES,
  formatHumanDate,
  formatHumanDateTime,
  fetchLeases
} from '../data'
import SideSheet from '../components/SideSheet.vue'

onMounted(async () => {
  await Promise.all([fetchLeases(), fetchAmendments()])
})

const amendments = ref<any[]>([])
const isLoadingAmendments = ref(false)
const showAmendmentSheet = ref(false)
const isSubmitting = ref(false)
const submissionError = ref('')
const submissionSuccess = ref('')

const amendmentForm = ref({
  leaseId: '',
  changeType: 'rent_adjustment' as 'rent_adjustment' | 'term_extension' | 'deposit_adjustment' | 'terms_amendment',
  effectiveDate: new Date().toISOString().slice(0, 10),
  newRent: 0,
  newEndDate: '',
  newDeposit: 0,
  reason: '',
  notes: ''
})

async function fetchAmendments() {
  isLoadingAmendments.value = true
  try {
    const headers: Record<string, string> = {}
    if (store.session.token) headers['Authorization'] = `Bearer ${store.session.token}`
    const res = await fetch('/api/leases-amendments', { headers })
    if (res.ok) {
      amendments.value = await res.json()
    }
  } catch (err) {
    console.error('Could not fetch amendments:', err)
  } finally {
    isLoadingAmendments.value = false
  }
}

const activeLeases = computed(() => {
  return store.leases.filter(l => l.status === 'active' || l.status === 'pending_deposit')
})

const selectedLease = computed(() => {
  return store.leases.find(l => l.id === amendmentForm.value.leaseId) || null
})

function openNewAmendment(preselectedLeaseId?: string) {
  submissionError.value = ''
  submissionSuccess.value = ''
  amendmentForm.value.leaseId = preselectedLeaseId || (activeLeases.value[0]?.id || '')
  const l = selectedLease.value || activeLeases.value[0]
  if (l) {
    amendmentForm.value.newRent = l.monthlyRent
    amendmentForm.value.newDeposit = l.depositAmount
    amendmentForm.value.newEndDate = l.endDate
  }
  showAmendmentSheet.value = true
}

async function handleSaveAmendment() {
  if (!amendmentForm.value.leaseId) {
    submissionError.value = 'Please select a lease agreement.'
    return
  }
  if (!amendmentForm.value.reason) {
    submissionError.value = 'Please enter a justification or reason for this amendment.'
    return
  }

  isSubmitting.value = true
  submissionError.value = ''

  try {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' }
    if (store.session.token) headers['Authorization'] = `Bearer ${store.session.token}`
    const res = await fetch(`/api/leases/${amendmentForm.value.leaseId}/amend`, {
      method: 'POST',
      headers,
      body: JSON.stringify(amendmentForm.value)
    })

    const data = await res.json()
    if (!res.ok) throw new Error(data.error || 'Failed to apply amendment')

    submissionSuccess.value = `Amendment recorded successfully for Lease ${data.lease?.leaseNumber || ''}!`
    await Promise.all([fetchLeases(), fetchAmendments()])
    setTimeout(() => {
      showAmendmentSheet.value = false
    }, 1200)
  } catch (err: any) {
    submissionError.value = err.message || 'Error saving amendment'
  } finally {
    isSubmitting.value = false
  }
}
</script>

<template>
  <div class="page-body">
    <!-- Header -->
    <header class="page-intro">
      <div>
        <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 6px;">
          <router-link to="/leases" class="back-link" style="display: inline-flex; align-items: center; gap: 4px; font-size: 0.85rem; color: #64748b; text-decoration: none;">
            <ArrowLeft :size="14" /> Back to Leases
          </router-link>
        </div>
        <p class="eyebrow">CONTRACT MANAGEMENT & AMENDMENTS</p>
        <h1>Lease Modifications & Changes</h1>
        <p>Record contractual adjustments, rate changes, term extensions, and legal addendums across your portfolio.</p>
      </div>

      <div class="intro-actions">
        <button type="button" class="primary-button" @click="openNewAmendment()">
          <Plus :size="15" />
          <span>New Lease Amendment</span>
        </button>
      </div>
    </header>

    <!-- Key Metrics Cards -->
    <section class="stats-grid" style="margin-bottom: 24px;">
      <article class="stat-card">
        <div class="stat-label">Active Leases</div>
        <div class="stat-value">{{ activeLeases.length }}</div>
        <div class="stat-trend positive">
          <span>Active Tenancies</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Contract Modifications</div>
        <div class="stat-value">{{ amendments.length }}</div>
        <div class="stat-trend neutral">
          <span>Recorded Amendments</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Portfolio Rate Adjustments</div>
        <div class="stat-value text-positive">
          {{ amendments.filter(a => a.changeType === 'rent_adjustment').length }}
        </div>
        <div class="stat-trend positive">
          <span>Rent Updates Logged</span>
        </div>
      </article>
    </section>

    <!-- Amendment Timeline / History Section -->
    <section class="structured-panel" style="margin-bottom: 24px;">
      <div class="panel-header-bar" style="display: flex; justify-content: space-between; align-items: center;">
        <div class="panel-header-title">
          <h2>Recorded Amendments & History ({{ amendments.length }})</h2>
          <p>Chronological audit trail of contractual modifications applied to residential agreements.</p>
        </div>
      </div>

      <div v-if="amendments.length > 0" class="table-responsive-wrapper">
        <div class="list-group-header" style="grid-template-columns: 140px 120px 1.2fr 130px 160px 80px; min-width: 780px;">
          <span>Effective Date</span>
          <span>Lease Ref</span>
          <span>Type & Reason</span>
          <span>Rate Change</span>
          <span>Resident & Unit</span>
          <span style="text-align: right;">Action</span>
        </div>

        <div
          v-for="am in amendments"
          :key="am.id"
          class="list-group-row"
          style="grid-template-columns: 140px 120px 1.2fr 130px 160px 80px; min-width: 780px;"
        >
          <div class="list-cell primary-row">
            <strong class="mono" style="font-size: 0.86rem; color: #0f172a;">{{ formatHumanDate(am.effectiveDate) }}</strong>
          </div>

          <div class="list-cell">
            <span class="mono" style="font-weight: 600; color: #2563eb;">{{ am.leaseNumber }}</span>
          </div>

          <div class="list-cell">
            <div>
              <strong style="font-size: 0.84rem; color: #0f172a; text-transform: capitalize; display: block;">
                {{ am.changeType.replace('_', ' ') }}
              </strong>
              <small style="color: #64748b;">{{ am.reason }}</small>
            </div>
          </div>

          <div class="list-cell">
            <span v-if="am.changeType === 'rent_adjustment'" style="font-size: 0.85rem; font-weight: 600; color: #059669;">
              {{ formatKES(am.newRent) }}/mo
            </span>
            <span v-else-if="am.changeType === 'term_extension'" style="font-size: 0.80rem; color: #475569;">
              Ext: {{ formatHumanDate(am.newEndDate) }}
            </span>
            <span v-else style="font-size: 0.82rem; color: #64748b;">
              Modified
            </span>
          </div>

          <div class="list-cell">
            <div>
              <strong style="font-size: 0.84rem; color: #1e293b; display: block;">{{ am.tenantName }}</strong>
              <small class="badge occupied" style="font-size: 0.68rem; padding: 2px 6px;">Unit {{ am.unitNumber }}</small>
            </div>
          </div>

          <div class="list-cell" style="justify-content: flex-end;">
            <router-link :to="`/leases/${am.leaseId}`" class="secondary-button" style="padding: 4px 10px; font-size: 0.76rem;">
              <span>View</span>
              <ChevronRight :size="12" />
            </router-link>
          </div>
        </div>
      </div>

      <div v-else style="padding: 36px; text-align: center; color: #64748b;">
        No lease amendments recorded yet. Click "New Lease Amendment" above to record rate adjustments or extensions.
      </div>
    </section>

    <!-- Side Sheet for Recording an Amendment -->
    <SideSheet
      :open="showAmendmentSheet"
      title="Record Lease Amendment"
      subtitle="Modify rates, terms, or duration of an agreement"
      width="480px"
      @close="showAmendmentSheet = false"
    >
      <form @submit.prevent="handleSaveAmendment" style="display: flex; flex-direction: column; gap: 16px;">
        <div v-if="submissionError" style="padding: 10px 14px; background-color: #fef2f2; border: 1px solid #fecaca; color: #991b1b; border-radius: 6px; font-size: 0.84rem;">
          {{ submissionError }}
        </div>
        <div v-if="submissionSuccess" style="padding: 10px 14px; background-color: #f0fdf4; border: 1px solid #bbf7d0; color: #166534; border-radius: 6px; font-size: 0.84rem;">
          {{ submissionSuccess }}
        </div>

        <div class="form-field">
          <label>Target Lease Agreement</label>
          <select v-model="amendmentForm.leaseId" required>
            <option value="" disabled>Select active lease...</option>
            <option v-for="l in activeLeases" :key="l.id" :value="l.id">
              {{ l.leaseNumber }} · Unit {{ l.unitNumber }} ({{ l.tenantName }})
            </option>
          </select>
        </div>

        <div class="form-field">
          <label>Amendment Category</label>
          <select v-model="amendmentForm.changeType" required>
            <option value="rent_adjustment">Monthly Rent Adjustment</option>
            <option value="term_extension">Term Extension / Renewal</option>
            <option value="deposit_adjustment">Security Deposit Adjustment</option>
            <option value="terms_amendment">Contractual Addendum / Terms Modification</option>
          </select>
        </div>

        <div class="form-field">
          <label>Effective Date</label>
          <input v-model="amendmentForm.effectiveDate" type="date" required />
        </div>

        <!-- Conditional Field: Rent Adjustment -->
        <div v-if="amendmentForm.changeType === 'rent_adjustment'" class="form-field">
          <label>New Monthly Rent (KES)</label>
          <input v-model.number="amendmentForm.newRent" type="number" min="1" required placeholder="e.g. 45000" />
          <small v-if="selectedLease" style="color: #64748b; font-size: 0.78rem;">
            Current Agreed Rate: <strong>{{ formatKES(selectedLease.monthlyRent) }}</strong>
          </small>
        </div>

        <!-- Conditional Field: Term Extension -->
        <div v-if="amendmentForm.changeType === 'term_extension'" class="form-field">
          <label>New Expiration Date</label>
          <input v-model="amendmentForm.newEndDate" type="date" required />
          <small v-if="selectedLease" style="color: #64748b; font-size: 0.78rem;">
            Current Expiration: <strong>{{ formatHumanDate(selectedLease.endDate) }}</strong>
          </small>
        </div>

        <!-- Conditional Field: Deposit Adjustment -->
        <div v-if="amendmentForm.changeType === 'deposit_adjustment'" class="form-field">
          <label>New Security Deposit Requirement (KES)</label>
          <input v-model.number="amendmentForm.newDeposit" type="number" min="0" required placeholder="e.g. 50000" />
        </div>

        <div class="form-field">
          <label>Justification / Reason</label>
          <input v-model="amendmentForm.reason" required placeholder="e.g. Annual contractual escalation, Tenant renewal" />
        </div>

        <div class="form-field">
          <label>Additional Notes / Addendum Text</label>
          <textarea v-model="amendmentForm.notes" rows="3" placeholder="Specify any legal terms or remarks to append to the agreement..."></textarea>
        </div>

        <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 16px; padding-top: 14px; border-top: 1px solid #f1f5f9;">
          <button type="button" class="secondary-button" @click="showAmendmentSheet = false">
            Cancel
          </button>
          <button type="submit" class="primary-button" :disabled="isSubmitting">
            {{ isSubmitting ? 'Applying Change...' : 'Apply & Save Amendment' }}
          </button>
        </div>
      </form>
    </SideSheet>
  </div>
</template>
