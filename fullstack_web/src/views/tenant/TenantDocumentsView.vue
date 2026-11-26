<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { FileText, Download, ShieldCheck, ChevronRight } from 'lucide-vue-next'
import { store, formatKES, formatHumanDate, fetchTenantProfile } from '../../data'

onMounted(async () => {
  await fetchTenantProfile()
})

const resident = computed(() => {
  return (
    store.tenants.find(t => t.id === store.session.tenantId || t.id === store.session.id) ||
    store.tenants.find(t => t.email.toLowerCase() === store.session.email.toLowerCase()) ||
    store.tenants[0]
  )
})

const leases = computed(() => {
  if (!resident.value) return []
  return store.leases.filter(l =>
    l.tenantId === resident.value?.id ||
    l.tenantName?.toLowerCase() === resident.value?.name?.toLowerCase() ||
    (resident.value?.currentUnitNumber && l.unitNumber === resident.value?.currentUnitNumber)
  )
})
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">RESIDENT DOCUMENTS</p>
        <h1>Tenancy Agreements</h1>
        <p>Access your residential lease agreements, building rules, and addenda.</p>
      </div>
    </header>

    <section class="structured-panel">
      <div class="panel-header-bar">
        <div class="panel-header-title">
          <h2>Agreements & Addenda</h2>
          <p>Digitally countersigned documents on file.</p>
        </div>
      </div>

      <div style="display: flex; flex-direction: column;">
        <div
          v-for="l in leases"
          :key="l.id"
          class="document-row"
          style="border-bottom: 1px solid #eef2f6;"
        >
          <span class="document-icon">
            <FileText :size="20" />
          </span>

          <div style="min-width: 0; flex: 1;">
            <div style="display: flex; align-items: center; gap: 8px;">
              <h2 style="font-size: 0.95rem; margin: 0;">Residential Lease — Unit {{ l.unitNumber }}</h2>
              <span :class="['badge', l.status]">{{ l.status }}</span>
            </div>
            <p style="font-size: 0.8rem; color: #64748b; margin-top: 3px;">
              Lease #{{ l.leaseNumber }} · {{ formatHumanDate(l.startDate) }} to {{ formatHumanDate(l.endDate) }} · Monthly Rent: {{ formatKES(l.monthlyRent) }}
            </p>
          </div>

          <button class="secondary-button" style="min-height: 30px; font-size: 0.78rem;">
            <Download :size="14" /> Download PDF
          </button>
        </div>

        <div class="document-row">
          <span class="document-icon">
            <ShieldCheck :size="20" />
          </span>
          <div style="min-width: 0; flex: 1;">
            <h2 style="font-size: 0.95rem; margin: 0;">Lapis Suites Resident Handbook & Rules</h2>
            <p style="font-size: 0.8rem; color: #64748b; margin-top: 3px;">
              Amenities usage, parking guidelines, noise regulations, and concierge protocols.
            </p>
          </div>
          <button class="secondary-button" style="min-height: 30px; font-size: 0.78rem;">
            <Download :size="14" /> Download PDF
          </button>
        </div>
      </div>
    </section>
  </div>
</template>
