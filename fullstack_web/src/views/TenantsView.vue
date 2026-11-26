<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import {
  Users,
  Search,
  Plus,
  ChevronRight,
  Phone,
  Mail
} from 'lucide-vue-next'
import { store, formatKES, getTenantFinancialStanding, fetchTenants, fetchLeases, fetchPayments } from '../data'
import PaginationControl from '../components/PaginationControl.vue'
import AddTenantSheet from '../components/AddTenantSheet.vue'
import type { Tenant } from '../types'

const tenantSearch = ref('')

onMounted(async () => {
  await Promise.all([fetchTenants(), fetchLeases(), fetchPayments()])
})

// Pagination
const currentPage = ref(1)
const pageSize = ref(10)

// Side Sheets
const isAddTenantOpen = ref(false)

const filteredTenants = computed(() => {
  const q = tenantSearch.value.trim().toLowerCase()
  if (!q) return store.tenants
  return store.tenants.filter(
    t =>
      t.name.toLowerCase().includes(q) ||
      t.email.toLowerCase().includes(q) ||
      t.phone.toLowerCase().includes(q) ||
      t.currentUnitNumber.toLowerCase().includes(q)
  )
})

function getTenantUnitNumber(t: Tenant): string {
  const lease = store.leases.find(l => l.tenantId === t.id && (l.status === 'active' || l.status === 'pending_deposit'))
  return lease?.unitNumber || ''
}

const paginatedTenants = computed(() => {
  const start = (currentPage.value - 1) * pageSize.value
  return filteredTenants.value.slice(start, start + pageSize.value)
})
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">RESIDENT DIRECTORY</p>
        <h1>Tenants & Residency</h1>
        <p>Active residents and unit assignments across Lapis Suites.</p>
      </div>

      <div class="intro-actions">
        <button class="primary-button" @click="isAddTenantOpen = true">
          <Plus :size="15" />
          <span>Add Tenant</span>
        </button>
      </div>
    </header>

    <!-- Tenants Table -->
    <section class="structured-panel">
      <div class="panel-header-bar" style="flex-wrap: wrap; gap: 12px;">
        <div class="panel-header-title">
          <h2>Active Residents ({{ store.tenants.length }})</h2>
        </div>
        <div class="page-search-bar" style="width: 240px; margin-left: auto;">
          <Search :size="15" class="search-icon" />
          <input v-model="tenantSearch" placeholder="Search residents..." @input="currentPage = 1" />
        </div>
      </div>

      <!-- Responsive Table Wrapper for Tablet & Small Laptop (Zero Aggressive Compression) -->
      <div class="table-responsive-wrapper">
        <!-- Desktop List Header (Single header, hidden <= 768px) -->
        <div class="list-group-header tenants-table-grid hide-mobile">
          <span>Resident</span>
          <span>Assigned Unit</span>
          <span>Contact</span>
          <span>Ledger Balance</span>
          <span style="text-align: right;">Action</span>
        </div>

        <!-- Rows -->
        <div
          v-for="t in paginatedTenants"
          :key="t.id"
          class="list-group-row"
        >
          <!-- Desktop Row Display (Single Horizontal Line with Ellipsis Protection) -->
          <div class="tenants-table-grid hide-mobile">
            <div class="list-cell">
              <div class="resident-chip">
                <div class="avatar" style="width: 32px; height: 32px; font-size: 0.8rem;">
                  {{ t.avatarInitials }}
                </div>
                <div class="list-cell-text">
                  <strong style="color: #0f172a; font-size: 0.90rem;">{{ t.name }}</strong>
                  <small style="color: #64748b;">{{ t.email }}</small>
                </div>
              </div>
            </div>

            <div class="list-cell">
              <span v-if="t.currentUnitNumber || getTenantUnitNumber(t)" class="badge occupied">
                Unit {{ t.currentUnitNumber || getTenantUnitNumber(t) }}
              </span>
              <span v-else class="badge vacant">Unassigned</span>
            </div>

            <div class="list-cell">
              <small class="mono" style="color: #475467;">{{ t.phone }}</small>
            </div>

            <div class="list-cell">
              <strong v-if="getTenantFinancialStanding(t).balance > 0" class="text-danger" style="font-size: 0.88rem;">
                {{ formatKES(getTenantFinancialStanding(t).balance) }} Arrears
              </strong>
              <strong v-else-if="getTenantFinancialStanding(t).accountCredit > 0" class="text-positive" style="font-size: 0.88rem;">
                {{ formatKES(getTenantFinancialStanding(t).accountCredit) }} Credit
              </strong>
              <span v-else class="text-settled" style="font-size: 0.84rem;">
                KES 0 (Settled)
              </span>
            </div>

            <div class="list-cell" style="justify-content: flex-end;">
              <router-link
                :to="`/tenants/${t.id}`"
                class="secondary-button"
                style="padding: 5px 12px; height: 32px; font-size: 0.8rem;"
              >
                <span>View</span>
                <ChevronRight :size="13" />
              </router-link>
            </div>
          </div>

          <!-- Mobile Directory Card: Avatar + Name + Metadata + Status + [View] -->
          <div class="dir-card-mobile show-mobile-only">
            <div class="dir-card-left">
              <div class="avatar" style="width: 34px; height: 34px; font-size: 0.78rem; flex: none;">
                {{ t.avatarInitials }}
              </div>
              <div class="dir-card-info">
                <strong class="dir-card-title">{{ t.name }}</strong>
                <span class="dir-card-meta">
                  {{ t.currentUnitNumber ? `Unit ${t.currentUnitNumber}` : 'Unassigned' }} · {{ t.phone }}
                </span>
              </div>
            </div>

            <div class="dir-card-right">
              <span v-if="getTenantFinancialStanding(t).balance > 0" class="badge overdue" style="font-size: 0.72rem;">
                Arrears ({{ formatKES(getTenantFinancialStanding(t).balance) }})
              </span>
              <span v-else-if="getTenantFinancialStanding(t).accountCredit > 0" class="badge paid" style="font-size: 0.72rem;">
                Credit ({{ formatKES(getTenantFinancialStanding(t).accountCredit) }})
              </span>
              <span v-else class="badge occupied" style="font-size: 0.72rem;">
                Settled
              </span>
              <router-link
                :to="`/tenants/${t.id}`"
                class="secondary-button"
                style="padding: 4px 10px; height: 30px; font-size: 0.78rem;"
              >
                View
              </router-link>
            </div>
          </div>
        </div>
      </div>

      <div v-if="paginatedTenants.length === 0" style="padding: 36px; text-align: center; color: #64748b;">
        No residents found matching your search.
      </div>

      <PaginationControl
        v-model:current-page="currentPage"
        v-model:page-size="pageSize"
        :total-items="filteredTenants.length"
      />
    </section>

    <!-- Add Tenant Side Sheet -->
    <AddTenantSheet
      :open="isAddTenantOpen"
      @close="isAddTenantOpen = false"
    />
  </div>
</template>

<style scoped>
.tenants-table-grid {
  grid-template-columns: 1.5fr 140px 140px 150px 100px;
  gap: 12px;
}

.tenants-mobile-grid {
  display: grid;
  grid-template-columns: 1.6fr 1fr 70px;
  gap: 8px;
}

.resident-chip {
  display: flex;
  align-items: center;
  gap: 10px;
}

.text-danger {
  color: #dc2626 !important;
}

.text-positive {
  color: #059669 !important;
}

.text-settled {
  color: #64748b;
}
</style>
