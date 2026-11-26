<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import {
  FileText,
  Search,
  Plus,
  ChevronRight,
  ExternalLink,
  Sliders
} from 'lucide-vue-next'
import { store, formatKES, getTenantFinancialStanding, fetchLeases, fetchUnits, fetchTenants } from '../data'
import PaginationControl from '../components/PaginationControl.vue'
import CreateLeaseSheet from '../components/CreateLeaseSheet.vue'
import type { Lease } from '../types'

const activeTab = ref<'all' | 'active' | 'transferred' | 'terminated'>('all')
const leaseSearch = ref('')

onMounted(async () => {
  await Promise.all([fetchLeases(), fetchUnits(), fetchTenants()])
})

// Pagination
const currentPage = ref(1)
const pageSize = ref(10)

// Side Sheet
const isCreateLeaseOpen = ref(false)

const filteredLeases = computed(() => {
  return store.leases.filter(l => {
    const matchesTab = activeTab.value === 'all' || l.status === activeTab.value
    const q = leaseSearch.value.trim().toLowerCase()
    const matchesSearch =
      !q ||
      l.leaseNumber.toLowerCase().includes(q) ||
      l.tenantName.toLowerCase().includes(q) ||
      l.unitNumber.toLowerCase().includes(q) ||
      l.unitType.toLowerCase().includes(q)

    return matchesTab && matchesSearch
  })
})

const paginatedLeases = computed(() => {
  const start = (currentPage.value - 1) * pageSize.value
  return filteredLeases.value.slice(start, start + pageSize.value)
})

function getTenantBalance(tenantId: string) {
  const t = store.tenants.find(tenant => tenant.id === tenantId)
  if (!t) return { balance: 0, text: 'KES 0', isArrears: false, isCredit: false }
  const standing = getTenantFinancialStanding(t)
  if (standing.balance > 0) {
    return { balance: standing.balance, text: `${formatKES(standing.balance)} Arrears`, isArrears: true, isCredit: false }
  } else if (standing.accountCredit > 0) {
    return { balance: standing.accountCredit, text: `${formatKES(standing.accountCredit)} Credit`, isArrears: false, isCredit: true }
  }
  return { balance: 0, text: 'KES 0 Settled', isArrears: false, isCredit: false }
}
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">LEGAL & TENANCY</p>
        <h1>Leases & Agreements</h1>
        <p>Active and historical lease agreements for Lapis Suites units.</p>
      </div>

      <div class="intro-actions">
        <router-link to="/leases/changes" class="secondary-button">
          <Sliders :size="15" />
          <span>Lease Changes</span>
        </router-link>
        <button class="primary-button" @click="isCreateLeaseOpen = true">
          <Plus :size="15" />
          <span>Create Lease</span>
        </button>
      </div>
    </header>

    <section class="structured-panel">
      <!-- Filters & Scoped Search -->
      <div class="panel-header-bar" style="flex-wrap: wrap; gap: 12px;">
        <div class="panel-filter-pills">
          <button
            :class="['filter-pill', { active: activeTab === 'all' }]"
            @click="activeTab = 'all'; currentPage = 1"
          >
            All Leases ({{ store.leases.length }})
          </button>
          <button
            :class="['filter-pill', { active: activeTab === 'active' }]"
            @click="activeTab = 'active'; currentPage = 1"
          >
            Active ({{ store.leases.filter(l => l.status === 'active').length }})
          </button>
          <button
            :class="['filter-pill', { active: activeTab === 'transferred' }]"
            @click="activeTab = 'transferred'; currentPage = 1"
          >
            Transferred ({{ store.leases.filter(l => l.status === 'transferred').length }})
          </button>
        </div>

        <div class="page-search-bar" style="width: 240px; margin-left: auto;">
          <Search :size="15" class="search-icon" />
          <input v-model="leaseSearch" placeholder="Search leases..." @input="currentPage = 1" />
        </div>
      </div>

      <!-- Responsive Table Wrapper for Tablet & Small Laptop (Zero Aggressive Compression) -->
      <div class="table-responsive-wrapper">
        <!-- Essential Fields Only: Unit Name (with Unit Type stacked), Tenant Name, Active State, Arrears/Credit Balance, Action (Single header, hidden <= 768px) -->
        <div class="list-group-header leases-essential-grid hide-mobile">
          <span>Unit</span>
          <span>Resident</span>
          <span>Active State</span>
          <span>Balance Standing</span>
          <span style="text-align: right;">Action</span>
        </div>

        <!-- Rows -->
        <div
          v-for="l in paginatedLeases"
          :key="l.id"
          class="list-group-row"
        >
          <!-- Desktop Row Layout (Single Horizontal Line with Ellipsis Protection) -->
          <div class="leases-essential-grid hide-mobile">
            <!-- Unit Name with Unit Type stacked directly underneath -->
            <div class="list-cell">
              <div class="list-cell-text">
                <strong style="color: #0f172a; font-size: 0.92rem;">Unit {{ l.unitNumber }}</strong>
                <small style="color: #64748b; text-transform: capitalize; font-size: 0.76rem;">{{ l.unitType.replace('-', ' ') }}</small>
              </div>
            </div>

            <!-- Tenant Name -->
            <div class="list-cell">
              <strong style="color: #1e293b; font-size: 0.88rem;">{{ l.tenantName }}</strong>
            </div>

            <!-- Active State -->
            <div class="list-cell">
              <span :class="['badge', l.status]" style="text-transform: capitalize;">● {{ l.status.replace('_', ' ') }}</span>
            </div>

            <!-- Current Arrears or Credit Balance -->
            <div class="list-cell">
              <strong
                :class="{
                  'text-danger': getTenantBalance(l.tenantId).isArrears,
                  'text-positive': getTenantBalance(l.tenantId).isCredit
                }"
                style="font-size: 0.88rem;"
              >
                {{ getTenantBalance(l.tenantId).text }}
              </strong>
            </div>

            <!-- Clear View Button navigating to Dedicated Page -->
            <div class="list-cell" style="justify-content: flex-end;">
              <router-link :to="`/leases/${l.id}`" class="secondary-button" style="padding: 5px 12px; height: 32px; font-size: 0.8rem;">
                <span>View</span>
                <ChevronRight :size="13" />
              </router-link>
            </div>
          </div>

          <!-- Mobile Directory Card: Unit & Resident + Balance Standing + [View] -->
          <div class="dir-card-mobile show-mobile-only">
            <div class="dir-card-left">
              <div class="dir-card-info">
                <strong class="dir-card-title">Unit {{ l.unitNumber }} · {{ l.tenantName }}</strong>
                <span
                  class="dir-card-meta"
                  :class="{
                    'text-danger': getTenantBalance(l.tenantId).isArrears,
                    'text-positive': getTenantBalance(l.tenantId).isCredit
                  }"
                >
                  {{ getTenantBalance(l.tenantId).text }} · {{ formatKES(l.monthlyRent) }}/mo
                </span>
              </div>
            </div>

            <div class="dir-card-right">
              <span :class="['badge', l.status]" style="font-size: 0.72rem; text-transform: capitalize;">● {{ l.status.replace('_', ' ') }}</span>
              <router-link
                :to="`/leases/${l.id}`"
                class="secondary-button"
                style="padding: 4px 10px; height: 30px; font-size: 0.78rem;"
              >
                View
              </router-link>
            </div>
          </div>
        </div>
      </div>

      <div v-if="paginatedLeases.length === 0" style="padding: 36px; text-align: center; color: #64748b;">
        No lease records found.
      </div>

      <PaginationControl
        v-model:current-page="currentPage"
        v-model:page-size="pageSize"
        :total-items="filteredLeases.length"
      />
    </section>

    <!-- Create Lease Side Sheet (Updated with SearchableSelect) -->
    <CreateLeaseSheet
      :open="isCreateLeaseOpen"
      @close="isCreateLeaseOpen = false"
    />
  </div>
</template>

<style scoped>
.leases-essential-grid {
  grid-template-columns: 140px 1.4fr 120px 1.4fr 110px;
  gap: 12px;
}

.leases-mobile-grid {
  display: grid;
  grid-template-columns: 1.4fr 1.2fr 75px;
  gap: 8px;
}

.text-danger {
  color: #dc2626 !important;
}

.text-positive {
  color: #059669 !important;
}
</style>
