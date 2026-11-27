<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { FileText, Download, ShieldCheck, ChevronDown, ChevronUp } from 'lucide-vue-next'
import { store, propertySettings, formatKES, formatHumanDate, fetchTenantProfile } from '../../data'
import LoadingSkeleton from '../../components/LoadingSkeleton.vue'
import { downloadLeaseAgreementPdf, downloadResidentHandbookPdf } from '../../utils/leaseAgreementGenerator'
import type { Lease } from '../../types'

const isLoading = ref(true)
const expandedLeaseId = ref<string | null>(null)

onMounted(async () => {
  try {
    await fetchTenantProfile()
  } finally {
    isLoading.value = false
  }
})

const resident = computed(() => {
  return (
    store.tenants.find(t => store.session.email && t.email && t.email.toLowerCase() === store.session.email.toLowerCase()) ||
    store.tenants.find(t => store.session.tenantId && t.id === store.session.tenantId) ||
    store.tenants.find(t => store.session.id && t.id === store.session.id) ||
    null
  )
})

const leases = computed(() => {
  if (!resident.value) return []
  return store.leases.filter(l => l.tenantId === resident.value?.id)
})

function handleDownloadLease(lease: Lease) {
  const unit = store.units.find(u => u.id === lease.unitId || u.unitNumber === lease.unitNumber) || null
  downloadLeaseAgreementPdf(lease, resident.value, unit)
}

function togglePreview(leaseId: string) {
  expandedLeaseId.value = expandedLeaseId.value === leaseId ? null : leaseId
}
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">RESIDENT DOCUMENTS</p>
        <h1>Tenancy Agreements</h1>
        <p>Access and download your formal residential tenancy agreements, payment schedule, and house rules.</p>
      </div>
    </header>

    <LoadingSkeleton v-if="isLoading && !resident" variant="list" :rows="3" />

    <section v-else class="structured-panel">
      <div class="panel-header-bar">
        <div class="panel-header-title">
          <h2>Agreements &amp; Addenda</h2>
          <p>Formal Residential Tenancy Agreements governed by the Laws of Kenya.</p>
        </div>
      </div>

      <div style="display: flex; flex-direction: column;">
        <div
          v-for="l in leases"
          :key="l.id"
          style="border-bottom: 1px solid #eef2f6;"
        >
          <div class="document-row">
            <span class="document-icon">
              <FileText :size="20" />
            </span>

            <div style="min-width: 0; flex: 1;">
              <div style="display: flex; align-items: center; gap: 8px; flex-wrap: wrap;">
                <h2 style="font-size: 0.95rem; margin: 0;">Residential Tenancy Agreement — Unit {{ l.unitNumber }}</h2>
                <span :class="['badge', l.status]">{{ l.status }}</span>
              </div>
              <p style="font-size: 0.8rem; color: #64748b; margin-top: 3px;">
                Agreement #{{ l.leaseNumber }} · {{ formatHumanDate(l.startDate) }} to {{ formatHumanDate(l.endDate) }} · Rent: {{ formatKES(l.monthlyRent) }}/mo · Deposit: {{ formatKES(l.depositAmount) }}
              </p>
            </div>

            <div style="display: flex; align-items: center; gap: 8px; flex-wrap: wrap;">
              <button
                type="button"
                class="secondary-button"
                style="min-height: 30px; font-size: 0.78rem;"
                @click="togglePreview(l.id)"
              >
                <ChevronUp v-if="expandedLeaseId === l.id" :size="14" />
                <ChevronDown v-else :size="14" />
                <span>{{ expandedLeaseId === l.id ? 'Hide Terms' : 'View Terms' }}</span>
              </button>
              <button
                type="button"
                class="primary-button"
                style="min-height: 30px; font-size: 0.78rem;"
                @click="handleDownloadLease(l)"
              >
                <Download :size="14" /> Download PDF
              </button>
            </div>
          </div>

          <div
            v-if="expandedLeaseId === l.id"
            style="margin: 0 20px 18px; padding: 16px 18px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 10px; font-size: 0.82rem; color: #334155; line-height: 1.55;"
          >
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 10px; margin-bottom: 12px; padding-bottom: 12px; border-bottom: 1px solid #e2e8f0;">
              <div><strong>Landlord:</strong> {{ propertySettings.paybillRecipientName || 'LAPIS APARTMENTS LIMITED' }}</div>
              <div><strong>Tenant:</strong> {{ resident?.name || l.tenantName }}</div>
              <div><strong>Premises:</strong> Unit {{ l.unitNumber }} ({{ l.unitType }})</div>
              <div><strong>Official Paybill:</strong> {{ propertySettings.paybillNumber || '522533' }} · Acc {{ propertySettings.accountNumber || '8107578' }}</div>
            </div>
            <p style="margin: 0 0 8px;"><strong>1. Rent &amp; Due Date:</strong> {{ formatKES(l.monthlyRent) }} payable in advance on or before Day {{ propertySettings.rentDueDay || 5 }} of each month strictly to M-Pesa Paybill {{ propertySettings.paybillNumber || '522533' }}, Account {{ propertySettings.accountNumber || '8107578' }} ({{ propertySettings.paybillRecipientName || 'LAPIS APARTMENTS LIMITED' }}).</p>
            <p style="margin: 0 0 8px;"><strong>2. Security Deposit:</strong> {{ formatKES(l.depositAmount) }} ({{ l.depositPaid ? 'Verified Paid' : 'Pending' }}), refundable within 30 days of vacating subject to joint inspection and clearance of arrears/utilities.</p>
            <p style="margin: 0 0 8px;"><strong>3. Notice &amp; Conduct:</strong> Minimum 1 calendar month written notice prior to move-out; strictly private residential use with no unauthorized subletting; quiet hours 10:00 PM – 6:00 AM.</p>
            <p v-if="l.terms" style="margin: 0 0 8px;"><strong>4. Special Notes:</strong> {{ l.terms }}</p>
            <p style="margin: 0; font-size: 0.77rem; color: #b45309; font-weight: 600;">
              NB: To avoid fraud and losing money, DO NOT pay rent to any other account or to any personal numbers. Download the full PDF above for all 8 clauses &amp; signature block.
            </p>
          </div>
        </div>

        <div v-if="leases.length === 0" style="padding: 24px 20px; border-bottom: 1px solid #eef2f6; color: #64748b; font-size: 0.85rem;">
          No active tenancy agreements are currently assigned to your account.
        </div>

        <div class="document-row">
          <span class="document-icon">
            <ShieldCheck :size="20" />
          </span>
          <div style="min-width: 0; flex: 1;">
            <h2 style="font-size: 0.95rem; margin: 0;">Lapis Suites Resident Handbook &amp; House Rules</h2>
            <p style="font-size: 0.8rem; color: #64748b; margin-top: 3px;">
              Official payment policy, access control, quiet hours, parking guidelines, and move-out checklist.
            </p>
          </div>
          <button
            type="button"
            class="secondary-button"
            style="min-height: 30px; font-size: 0.78rem;"
            @click="downloadResidentHandbookPdf()"
          >
            <Download :size="14" /> Download PDF
          </button>
        </div>
      </div>
    </section>
  </div>
</template>
