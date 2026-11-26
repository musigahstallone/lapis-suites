<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import {
  Building2,
  Plus,
  Search,
  Sliders,
  ChevronRight,
  Edit2
} from 'lucide-vue-next'
import {
  store,
  formatKES,
  getUnitMonthlyRent,
  getUnitTypeConfig,
  fetchUnits,
  fetchUnitTypes
} from '../data'
import PaginationControl from '../components/PaginationControl.vue'
import UnitTypeSheet from '../components/UnitTypeSheet.vue'
import type { Unit, UnitType, UnitStatus, UnitTypeConfig } from '../types'

const emit = defineEmits<{
  (e: 'openAddUnit'): void
}>()

onMounted(async () => {
  await Promise.all([fetchUnits(), fetchUnitTypes()])
})

const activeViewTab = ref<'units' | 'types'>('units')
const activeFilter = ref<'all' | UnitType | UnitStatus>('all')
const unitSearch = ref('')

// Pagination
const currentPage = ref(1)
const pageSize = ref(10)

// Side sheet for Unit Types
const selectedTypeForEdit = ref<UnitTypeConfig | null>(null)
const isTypeSheetOpen = ref(false)

function getUnitTypeName(typeKey: string): string {
  const cfg = getUnitTypeConfig(typeKey)
  return cfg ? cfg.name : typeKey
}

const filteredUnits = computed(() => {
  return store.units.filter(u => {
    const matchesFilter =
      activeFilter.value === 'all' ||
      u.type === activeFilter.value ||
      u.status === activeFilter.value

    const q = unitSearch.value.trim().toLowerCase()
    const matchesSearch =
      !q ||
      u.unitNumber.toLowerCase().includes(q) ||
      u.type.toLowerCase().includes(q) ||
      getUnitTypeName(u.type).toLowerCase().includes(q) ||
      (getTenant(u.currentTenantId)?.name.toLowerCase().includes(q) ?? false)

    return matchesFilter && matchesSearch
  })
})

const paginatedUnits = computed(() => {
  const start = (currentPage.value - 1) * pageSize.value
  return filteredUnits.value.slice(start, start + pageSize.value)
})

function getTenant(tenantId: string | null) {
  if (!tenantId) return null
  return store.tenants.find(t => t.id === tenantId)
}

function openEditType(type: UnitTypeConfig) {
  selectedTypeForEdit.value = type
  isTypeSheetOpen.value = true
}

function openCreateType() {
  selectedTypeForEdit.value = null
  isTypeSheetOpen.value = true
}
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">PORTFOLIO UNITS</p>
        <h1>Units & Portfolio Management</h1>
        <p>Comprehensive inventory of studio, one-bedroom, and two-bedroom apartments.</p>
      </div>

      <div class="intro-actions">
        <button
          v-if="activeViewTab === 'units'"
          type="button"
          class="primary-button"
          @click="emit('openAddUnit')"
        >
          <Plus :size="15" />
          <span>Add Unit</span>
        </button>
        <button
          v-else
          type="button"
          class="primary-button"
          @click="openCreateType"
        >
          <Plus :size="15" />
          <span>New Unit Type</span>
        </button>
      </div>
    </header>

    <!-- Executive Tab Switcher -->
    <div class="units-tab-switcher">
      <button
        type="button"
        :class="['tab-pill', { active: activeViewTab === 'units' }]"
        @click="activeViewTab = 'units'"
      >
        <Building2 :size="15" />
        <span>Units Inventory</span>
        <span class="tab-count">{{ store.units.length }}</span>
      </button>
      <button
        type="button"
        :class="['tab-pill', { active: activeViewTab === 'types' }]"
        @click="activeViewTab = 'types'"
      >
        <Sliders :size="15" />
        <span>Unit Types Configuration</span>
        <span class="tab-count">{{ store.unitTypes.length }}</span>
      </button>
    </div>

    <!-- Section 1: Units Inventory Table -->
    <section v-if="activeViewTab === 'units'" class="structured-panel">
      <div class="panel-header-bar" style="flex-wrap: wrap; gap: 10px;">
        <div class="panel-filter-pills">
          <button
            :class="['filter-pill', { active: activeFilter === 'all' }]"
            @click="activeFilter = 'all'; currentPage = 1"
          >
            All ({{ store.units.length }})
          </button>
          <button
            :class="['filter-pill', { active: activeFilter === 'studio' }]"
            @click="activeFilter = 'studio'; currentPage = 1"
          >
            Studio
          </button>
          <button
            :class="['filter-pill', { active: activeFilter === 'one-bedroom' }]"
            @click="activeFilter = 'one-bedroom'; currentPage = 1"
          >
            1-Bedroom
          </button>
          <button
            :class="['filter-pill', { active: activeFilter === 'two-bedroom' }]"
            @click="activeFilter = 'two-bedroom'; currentPage = 1"
          >
            2-Bedroom
          </button>
          <button
            :class="['filter-pill', { active: activeFilter === 'vacant' }]"
            @click="activeFilter = 'vacant'; currentPage = 1"
          >
            Vacant ({{ store.units.filter(u => u.status === 'vacant').length }})
          </button>
          <button
            :class="['filter-pill', { active: activeFilter === 'occupied' }]"
            @click="activeFilter = 'occupied'; currentPage = 1"
          >
            Occupied ({{ store.units.filter(u => u.status === 'occupied').length }})
          </button>
        </div>

        <div class="page-search-bar" style="width: 220px; margin-left: auto;">
          <Search :size="15" class="search-icon" />
          <input v-model="unitSearch" placeholder="Filter units..." @input="currentPage = 1" />
        </div>
      </div>

      <!-- Zero-state when no units exist in the portfolio at all -->
      <div v-if="store.units.length === 0" class="empty-inventory-state">
        <div class="empty-state-icon-box">
          <Building2 :size="26" />
        </div>
        <h3 class="empty-state-title">No units in portfolio yet</h3>
        <p class="empty-state-desc">
          Standardized unit configurations are defined. Add physical units to your portfolio to begin tracking occupancy, resident leases, and rent payments.
        </p>
        <button
          type="button"
          class="primary-button"
          style="margin-top: 14px;"
          @click="emit('openAddUnit')"
        >
          <Plus :size="15" />
          <span>Add First Unit</span>
        </button>
      </div>

      <!-- Zero-state when search filter has no matching results -->
      <div v-else-if="paginatedUnits.length === 0" class="empty-search-state">
        <p style="color: #64748b; font-size: 0.9rem; margin-bottom: 8px;">No units match your active filter or search term.</p>
        <button
          type="button"
          class="secondary-button"
          style="padding: 4px 12px; font-size: 0.8rem;"
          @click="activeFilter = 'all'; unitSearch = ''"
        >
          Reset Filters
        </button>
      </div>

      <!-- Responsive Table Wrapper for Units -->
      <div v-else class="table-responsive-wrapper">
        <!-- Desktop List Header (5 columns) -->
        <div class="list-group-header units-table-grid hide-mobile">
          <span>Unit</span>
          <span>Unit Type</span>
          <span>Monthly Rent</span>
          <span>Occupancy Status</span>
          <span style="text-align: right;">Action</span>
        </div>

        <!-- Rows -->
        <div
          v-for="u in paginatedUnits"
          :key="u.id"
          class="list-group-row"
        >
          <!-- Desktop Row (5 columns matching header) -->
          <div class="units-table-grid hide-mobile">
            <div class="list-cell">
              <strong style="color: #0f172a; font-size: 0.92rem; font-weight: 600;">Unit {{ u.unitNumber }}</strong>
            </div>

            <div class="list-cell">
              <span class="unit-type-pill">{{ getUnitTypeName(u.type) }}</span>
            </div>

            <div class="list-cell">
              <strong style="color: #0f172a; font-size: 0.92rem; font-weight: 600;">{{ formatKES(getUnitMonthlyRent(u)) }}</strong>
              <small style="color: #64748b; margin-left: 2px;">/mo</small>
            </div>

            <div class="list-cell">
              <span :class="['badge', u.status]">● {{ u.status }}</span>
            </div>

            <div class="list-cell" style="justify-content: flex-end; gap: 6px;">
              <router-link
                :to="`/units/${u.id}/lease`"
                class="secondary-button"
                style="padding: 5px 10px; height: 32px; font-size: 0.78rem;"
              >
                <span>{{ u.status === 'vacant' ? 'Assign Lease' : 'Lease Changes' }}</span>
              </router-link>
              <router-link
                :to="`/units/${u.id}`"
                class="secondary-button"
                style="padding: 5px 12px; height: 32px; font-size: 0.8rem;"
              >
                <span>View</span>
                <ChevronRight :size="13" />
              </router-link>
            </div>
          </div>

          <!-- Mobile Directory Card -->
          <div class="dir-card-mobile show-mobile-only">
            <div class="dir-card-left">
              <div class="dir-card-info">
                <strong class="dir-card-title">Unit {{ u.unitNumber }}</strong>
                <span class="dir-card-meta">{{ getUnitTypeName(u.type) }} · {{ formatKES(getUnitMonthlyRent(u)) }}/mo</span>
              </div>
            </div>

            <div class="dir-card-right">
              <span :class="['badge', u.status]">● {{ u.status }}</span>
              <router-link
                :to="`/units/${u.id}`"
                class="secondary-button"
                style="padding: 4px 10px; height: 30px; font-size: 0.78rem;"
              >
                View
              </router-link>
            </div>
          </div>
        </div>

        <PaginationControl
          v-if="filteredUnits.length > pageSize"
          v-model:current-page="currentPage"
          v-model:page-size="pageSize"
          :total-items="filteredUnits.length"
        />
      </div>
    </section>

    <!-- Section 2: Standardized Unit Configurations Catalog -->
    <section v-else class="structured-panel">
      <div class="panel-header-bar">
        <div class="panel-header-title">
          <h2>Standardized Unit Configurations ({{ store.unitTypes.length }})</h2>
          <p>Features, base rents, and security deposit rules are inherited by all linked units.</p>
        </div>
      </div>

      <div class="table-responsive-wrapper">
        <!-- Desktop List Header (5 columns) -->
        <div class="list-group-header types-list-grid hide-mobile">
          <span>Unit Type</span>
          <span>Base Monthly Rent</span>
          <span>Security Deposit Rule</span>
          <span>Inherited Features</span>
          <span style="text-align: right;">Action</span>
        </div>

        <!-- Rows -->
        <div
          v-for="ut in store.unitTypes"
          :key="ut.id"
          class="list-group-row"
        >
          <!-- Desktop Row: Only visible on screens > 768px -->
          <div class="types-list-grid hide-mobile">
            <div class="list-cell">
              <span class="unit-type-pill">{{ ut.name }}</span>
            </div>

            <div class="list-cell">
              <strong style="color: #0f172a; font-size: 0.92rem; font-weight: 600;">{{ formatKES(ut.baseRent) }}</strong>
              <small style="color: #64748b; margin-left: 2px;">/mo</small>
            </div>

            <div class="list-cell" style="color: #334155; font-size: 0.86rem;">
              <span>{{ ut.depositMultiplier }}× Rent ({{ formatKES(ut.baseRent * ut.depositMultiplier) }})</span>
            </div>

            <div class="list-cell" style="color: #64748b; font-size: 0.82rem; line-height: 1.4;">
              <span>{{ ut.features && ut.features.length ? ut.features.slice(0, 3).join(', ') : 'Standard fixtures' }}</span>
            </div>

            <div class="list-cell" style="justify-content: flex-end;">
              <button
                type="button"
                class="secondary-button"
                style="padding: 5px 12px; height: 32px; font-size: 0.8rem;"
                @click="openEditType(ut)"
              >
                <Edit2 :size="13" />
                <span>Edit</span>
              </button>
            </div>
          </div>

          <!-- Mobile Card: Only visible on screens <= 768px -->
          <div class="type-card-mobile show-mobile-only">
            <div class="type-card-mobile-header">
              <div>
                <span class="unit-type-pill">{{ ut.name }}</span>
                <div style="margin-top: 4px;">
                  <strong style="color: #0f172a; font-size: 0.95rem; font-weight: 600;">{{ formatKES(ut.baseRent) }}</strong>
                  <small style="font-size: 0.75rem; color: #64748b; margin-left: 2px;">/mo</small>
                </div>
              </div>
              <button
                type="button"
                class="secondary-button"
                style="padding: 4px 10px; height: 30px; font-size: 0.78rem;"
                @click="openEditType(ut)"
              >
                <Edit2 :size="13" />
                <span>Edit</span>
              </button>
            </div>
            <div class="type-card-mobile-body">
              <span>Deposit: <strong>{{ ut.depositMultiplier }}× ({{ formatKES(ut.baseRent * ut.depositMultiplier) }})</strong></span>
              <span v-if="ut.features && ut.features.length">• {{ ut.features.slice(0, 2).join(', ') }}</span>
            </div>
          </div>
        </div>

        <div v-if="store.unitTypes.length === 0" class="empty-inventory-state">
          <div class="empty-state-icon-box">
            <Sliders :size="26" />
          </div>
          <h3 class="empty-state-title">No unit configurations found</h3>
          <p class="empty-state-desc">
            Define standardized unit templates with base rents and security deposit rules to streamline portfolio inventory.
          </p>
          <button
            type="button"
            class="primary-button"
            style="margin-top: 14px;"
            @click="openCreateType"
          >
            <Plus :size="15" />
            <span>Create Unit Type</span>
          </button>
        </div>
      </div>
    </section>

    <!-- Side Sheet for Unit Types -->
    <UnitTypeSheet
      :open="isTypeSheetOpen"
      :unit-type="selectedTypeForEdit"
      @close="isTypeSheetOpen = false"
    />
  </div>
</template>

<style scoped>
.units-tab-switcher {
  display: inline-flex;
  gap: 4px;
  background: #f1f5f9;
  padding: 4px;
  border-radius: 8px;
  border: 1px solid #e2e8f0;
  margin-bottom: 20px;
}

.tab-pill {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 6px 14px;
  border-radius: 6px;
  font-size: 0.84rem;
  font-weight: 500;
  color: #64748b;
  background: transparent;
  border: none;
  cursor: pointer;
  transition: all 0.15s ease;
}

.tab-pill:hover {
  color: #0f172a;
}

.tab-pill.active {
  background: #ffffff;
  color: #0f172a;
  font-weight: 600;
  box-shadow: 0 1px 3px rgba(15, 23, 42, 0.08);
}

.tab-count {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 1px 7px;
  border-radius: 99px;
  background: #e2e8f0;
  font-size: 0.74rem;
  font-weight: 600;
  color: #475467;
}

.tab-pill.active .tab-count {
  background: #0f172a;
  color: #ffffff;
}

.units-table-grid {
  display: grid;
  grid-template-columns: 130px 180px 150px 140px 1fr;
  gap: 16px;
  align-items: center;
}

.types-list-grid {
  display: grid;
  grid-template-columns: 200px 160px 220px 1.5fr 90px;
  gap: 16px;
  align-items: center;
}

.type-card-mobile {
  display: none;
}

.empty-inventory-state {
  padding: 48px 24px;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
}

.empty-state-icon-box {
  width: 52px;
  height: 52px;
  border-radius: 12px;
  background: #f1f5f9;
  border: 1px solid #e2e8f0;
  color: #64748b;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 14px;
}

.empty-state-title {
  font-size: 1.02rem;
  font-weight: 600;
  color: #0f172a;
  margin: 0 0 6px 0;
}

.empty-state-desc {
  font-size: 0.86rem;
  color: #64748b;
  max-width: 440px;
  margin: 0;
  line-height: 1.5;
}

.empty-search-state {
  padding: 36px 20px;
  text-align: center;
}

@media (max-width: 768px) {
  .type-card-mobile {
    display: flex;
    flex-direction: column;
    gap: 8px;
    width: 100%;
  }

  .type-card-mobile-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
  }

  .type-card-mobile-body {
    font-size: 0.78rem;
    color: #475467;
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    border-top: 1px solid #f1f5f9;
    padding-top: 6px;
  }
}
</style>
