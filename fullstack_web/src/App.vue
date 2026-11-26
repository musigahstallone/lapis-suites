<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  Building2,
  Users,
  FileText,
  CreditCard,
  ShieldCheck,
  Home,
  Settings,
  LogOut,
  Wrench,
  Sliders,
  FileCheck
} from 'lucide-vue-next'
import GlobalHeader from './components/GlobalHeader.vue'
import AddUnitSheet from './components/AddUnitSheet.vue'
import UnitTransferSheet from './components/UnitTransferSheet.vue'
import { store, logout, fetchDashboard, fetchTenantProfile } from './data'

const route = useRoute()
const router = useRouter()

onMounted(async () => {
  if (store.session.isAuthenticated) {
    if (store.session.role === 'landlord') {
      await fetchDashboard()
    } else {
      await fetchTenantProfile()
    }
  }
})

const sidebarOpen = ref(false)

// Global Side Sheets (Zero Modal Architecture)
const showAddUnitSheet = ref(false)
const showTransferSheet = ref(false)
const transferTenantId = ref<string | undefined>(undefined)

const pendingMaintenanceCount = computed(() => {
  return (store.maintenanceRequests || []).filter(r => r.status === 'pending').length
})

// Check if currently on an auth or standalone public payment page
const isAuthRoute = computed(() => {
  return ['login', 'register', 'forgot-password', 'verify-code', 'reset-password', 'public-pay', 'public-pay-link'].includes(route.name as string)
})

function handleSignOut() {
  logout()
  sidebarOpen.value = false
  router.push('/login')
}

function openTransfer(tenantId?: string) {
  transferTenantId.value = tenantId
  showTransferSheet.value = true
}

function openAddUnit() {
  showAddUnitSheet.value = true
}
</script>

<template>
  <!-- Standalone Authentication Layout -->
  <router-view v-if="isAuthRoute" />

  <!-- Authenticated Application Shell -->
  <div v-else class="app-shell">
    <!-- Sidebar Navigation -->
    <aside :class="['sidebar', { open: sidebarOpen }]">
      <!-- Top Brand -->
      <router-link
        :to="store.session.role === 'landlord' ? '/dashboard' : '/tenant/home'"
        class="brand"
        @click="sidebarOpen = false"
      >
        <span class="brand-mark">L</span>
        <div>
          <div>LAPIS SUITES</div>
          <div class="brand-tag">Urban Executive Living</div>
        </div>
      </router-link>

      <!-- Landlord Navigation -->
      <template v-if="store.session.role === 'landlord'">
        <div class="nav-section-title">Management</div>
        <nav class="nav-list">
          <router-link
            to="/dashboard"
            :class="['nav-item', { active: route.name === 'dashboard' }]"
            @click="sidebarOpen = false"
          >
            <Home :size="16" />
            <span>Dashboard</span>
          </router-link>

          <router-link
            to="/units"
            :class="['nav-item', { active: route.name === 'units' || route.name === 'unit-details' || route.name === 'unit-lease' }]"
            @click="sidebarOpen = false"
          >
            <Building2 :size="16" />
            <span>Units</span>
            <span class="nav-badge">{{ store.units.length }}</span>
          </router-link>

          <router-link
            to="/tenants"
            :class="['nav-item', { active: route.name === 'tenants' || route.name === 'tenant-details' || route.name === 'tenant-lease-changes' }]"
            @click="sidebarOpen = false"
          >
            <Users :size="16" />
            <span>Tenants</span>
            <span class="nav-badge">{{ store.tenants.length }}</span>
          </router-link>

          <router-link
            to="/leases"
            :class="['nav-item', { active: route.name === 'leases' || route.name === 'lease-details' }]"
            @click="sidebarOpen = false"
          >
            <FileText :size="16" />
            <span>Leases</span>
          </router-link>

          <router-link
            to="/leases/changes"
            :class="['nav-item', { active: route.name === 'lease-changes' }]"
            @click="sidebarOpen = false"
          >
            <Sliders :size="16" />
            <span>Lease Changes</span>
          </router-link>

          <router-link
            to="/maintenance"
            :class="['nav-item', { active: route.name === 'maintenance' }]"
            @click="sidebarOpen = false"
          >
            <Wrench :size="16" />
            <span>Maintenance</span>
            <span v-if="pendingMaintenanceCount > 0" class="nav-badge" style="background: #fef3c7; color: #b45309;">
              {{ pendingMaintenanceCount }}
            </span>
          </router-link>
        </nav>

        <div class="nav-section-title">Finance</div>
        <nav class="nav-list">
          <router-link
            to="/payments"
            :class="['nav-item', { active: route.name === 'payments' || route.name === 'payments-record' }]"
            @click="sidebarOpen = false"
          >
            <CreditCard :size="16" />
            <span>Payments</span>
          </router-link>

          <router-link
            to="/reconciliation"
            :class="['nav-item', { active: route.name === 'reconciliation' }]"
            @click="sidebarOpen = false"
          >
            <ShieldCheck :size="16" />
            <span>Reconciliation</span>
          </router-link>

          <router-link
            to="/audit"
            :class="['nav-item', { active: route.name === 'audit-reflections' }]"
            @click="sidebarOpen = false"
          >
            <FileCheck :size="16" />
            <span>Audit Reflections</span>
          </router-link>

          <router-link
            to="/settings"
            :class="['nav-item', { active: route.name === 'settings' }]"
            @click="sidebarOpen = false"
          >
            <Settings :size="16" />
            <span>Settings</span>
          </router-link>
        </nav>
      </template>

      <!-- Tenant Navigation -->
      <template v-else>
        <div class="nav-section-title">Resident Portal</div>
        <nav class="nav-list">
          <router-link
            to="/tenant/home"
            :class="['nav-item', { active: route.name === 'tenant-home' }]"
            @click="sidebarOpen = false"
          >
            <Home :size="16" />
            <span>My Home</span>
          </router-link>

          <router-link
            to="/tenant/payments"
            :class="['nav-item', { active: route.name === 'tenant-payments' || route.name === 'tenant-pay' }]"
            @click="sidebarOpen = false"
          >
            <CreditCard :size="16" />
            <span>Payments</span>
          </router-link>

          <router-link
            to="/tenant/maintenance"
            :class="['nav-item', { active: route.name === 'tenant-maintenance' }]"
            @click="sidebarOpen = false"
          >
            <Wrench :size="16" />
            <span>Maintenance</span>
          </router-link>

          <router-link
            to="/tenant/documents"
            :class="['nav-item', { active: route.name === 'tenant-documents' }]"
            @click="sidebarOpen = false"
          >
            <FileText :size="16" />
            <span>Documents</span>
          </router-link>

          <router-link
            to="/tenant/settings"
            :class="['nav-item', { active: route.name === 'tenant-settings' }]"
            @click="sidebarOpen = false"
          >
            <Settings :size="16" />
            <span>Settings</span>
          </router-link>
        </nav>
      </template>

      <!-- User Details & Sign Out STRICTLY at the Bottom of Sidebar across all views -->
      <div class="sidebar-user-footer">
        <div class="account-chip" style="margin: 0;">
          <div class="avatar">
            {{ store.session.avatarInitials || 'U' }}
          </div>
          <div class="account-info">
            <strong>{{ store.session.name }}</strong>
            <small v-if="store.session.role === 'landlord'">Property Manager</small>
            <small v-else>Unit {{ store.session.unitNumber || '6604' }}</small>
          </div>
          <button
            type="button"
            class="signout-button"
            title="Sign out of portal"
            aria-label="Sign out"
            @click="handleSignOut"
          >
            <LogOut :size="16" />
          </button>
        </div>
      </div>
    </aside>

    <!-- Mobile Overlay Backdrop -->
    <div
      :class="['mobile-nav-overlay', { open: sidebarOpen }]"
      @click="sidebarOpen = false"
    ></div>

    <!-- Main Content Area -->
    <div class="main-content">
      <GlobalHeader
        :sidebar-open="sidebarOpen"
        @toggle-sidebar="sidebarOpen = !sidebarOpen"
      />

      <router-view
        @open-add-unit="openAddUnit"
        @open-transfer="openTransfer"
      />
    </div>

    <!-- Contextual Slide-Over Side Sheets (Zero-Modal Architecture) -->
    <AddUnitSheet
      :open="showAddUnitSheet"
      @close="showAddUnitSheet = false"
    />

    <UnitTransferSheet
      :open="showTransferSheet"
      :default-tenant-id="transferTenantId"
      @close="showTransferSheet = false"
    />
  </div>
</template>
