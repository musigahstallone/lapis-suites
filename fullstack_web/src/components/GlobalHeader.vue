<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import {
  Bell,
  Menu,
  CheckCircle2,
  ShieldCheck,
  Wrench,
  CreditCard,
  Check,
  AlertTriangle,
  Search,
  X
} from 'lucide-vue-next'
import { store, markNotificationRead, markAllNotificationsRead, formatHumanDateTime, formatKES } from '../data'
import type { AppNotification } from '../types'

const props = defineProps<{
  sidebarOpen: boolean
}>()

const emit = defineEmits<{
  (e: 'toggleSidebar'): void
}>()

const router = useRouter()
const route = useRoute()
const showNotifications = ref(false)
const isMobileSearchExpanded = ref(false)
const mobileSearchInput = ref<HTMLInputElement | null>(null)
const notifWrapperRef = ref<HTMLElement | null>(null)

const currentPageTitle = computed(() => {
  const id = typeof route.params.id === 'string' ? route.params.id : ''
  if (route.name === 'unit-details' && id) {
    const unit = store.units.find(u => u.id === id)
    if (unit) return `Unit ${unit.unitNumber}`
  }
  if (route.name === 'unit-lease' && id) {
    const unit = store.units.find(u => u.id === id)
    if (unit) return `Unit ${unit.unitNumber} · Lease`
  }
  if (route.name === 'tenant-details' && id) {
    const tenant = store.tenants.find(t => t.id === id)
    if (tenant) return tenant.name
  }
  if (route.name === 'tenant-lease-changes' && id) {
    const tenant = store.tenants.find(t => t.id === id)
    if (tenant) return `${tenant.name} · Lease Changes`
  }
  if (route.name === 'lease-details' && id) {
    const lease = store.leases.find(l => l.id === id)
    if (lease) return lease.leaseNumber
  }
  return (route.meta?.title as string) || 'Dashboard'
})

function handleOutsidePointerDown(e: PointerEvent) {
  if (!showNotifications.value) return
  const target = e.target as Node | null
  if (notifWrapperRef.value && target && !notifWrapperRef.value.contains(target)) {
    showNotifications.value = false
  }
}

function handleGlobalKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape') {
    if (showNotifications.value) showNotifications.value = false
    if (isMobileSearchExpanded.value) {
      isMobileSearchExpanded.value = false
      store.searchQuery = ''
    }
  }
}

onMounted(() => {
  document.addEventListener('pointerdown', handleOutsidePointerDown)
  document.addEventListener('keydown', handleGlobalKeydown)
})

onUnmounted(() => {
  document.removeEventListener('pointerdown', handleOutsidePointerDown)
  document.removeEventListener('keydown', handleGlobalKeydown)
})

function handleToggleSidebar() {
  showNotifications.value = false
  emit('toggleSidebar')
}

function toggleMobileSearch() {
  isMobileSearchExpanded.value = !isMobileSearchExpanded.value
  if (isMobileSearchExpanded.value) {
    showNotifications.value = false
    setTimeout(() => {
      mobileSearchInput.value?.focus()
    }, 100)
  } else {
    store.searchQuery = ''
  }
}

function selectSearchResult(url: string) {
  isMobileSearchExpanded.value = false
  store.searchQuery = ''
  router.push(url)
}

const searchResults = computed(() => {
  const q = store.searchQuery.trim().toLowerCase()
  if (!q) return { units: [], tenants: [], leases: [] }

  const units = (store.units || []).filter(u =>
    u.unitNumber.toLowerCase().includes(q) || u.type.toLowerCase().includes(q)
  ).slice(0, 4)

  const tenants = (store.tenants || []).filter(t =>
    t.name.toLowerCase().includes(q) ||
    t.phone.toLowerCase().includes(q) ||
    t.currentUnitNumber.toLowerCase().includes(q)
  ).slice(0, 4)

  const leases = (store.leases || []).filter(l =>
    l.leaseNumber.toLowerCase().includes(q) ||
    l.tenantName.toLowerCase().includes(q) ||
    l.unitNumber.toLowerCase().includes(q)
  ).slice(0, 4)

  return { units, tenants, leases }
})

const totalMatches = computed(() => {
  return searchResults.value.units.length + searchResults.value.tenants.length + searchResults.value.leases.length
})

const userNotifications = computed<AppNotification[]>(() => {
  const all = store.notifications || []
  const role = store.session.role
  const tenantId = store.session.id

  return all.filter(n => {
    if (n.role === 'all') return true
    if (role === 'landlord') return n.role === 'landlord'
    if (role === 'tenant') {
      if (n.role === 'tenant') {
        if (!n.tenantId) return true
        return n.tenantId === tenantId
      }
      return false
    }
    return true
  })
})

const unreadCount = computed(() => {
  return userNotifications.value.filter(n => !n.read).length
})

function toggleNotifications() {
  showNotifications.value = !showNotifications.value
}

function handleNotificationClick(notif: AppNotification) {
  markNotificationRead(notif.id)
  showNotifications.value = false
  if (notif.link) {
    router.push(notif.link)
  }
}

function handleMarkAllRead() {
  markAllNotificationsRead(store.session.role)
}
</script>

<template>
  <div class="header-wrapper">
    <header class="header">
      <!-- Mobile Top-Left Logo (Matches desktop sidebar branding) -->
      <div class="header-left">
        <router-link
          :to="store.session.role === 'landlord' ? '/dashboard' : '/tenant/home'"
          class="mobile-brand"
        >
          <span class="brand-mark">L</span>
          <div class="mobile-brand-text">
            <strong>LAPIS SUITES</strong>
            <small>Urban Executive Living</small>
          </div>
        </router-link>

        <!-- Desktop Page Title (Hides LAPIS SUITES title on large screens as it is displayed in the desktop sidebar) -->
        <div class="desktop-page-title hide-mobile">
          <h1>{{ currentPageTitle }}</h1>
        </div>
      </div>

      <!-- Right-Side Controls: Search, Notifications & Menu Toggle on Far-Right -->
      <div class="header-right">
        <!-- Search Trigger Button: Click opens, click again closes -->
        <button
          type="button"
          class="header-icon-btn"
          :class="{ active: isMobileSearchExpanded }"
          title="Toggle search"
          aria-label="Search"
          @click="toggleMobileSearch"
        >
          <Search :size="17" />
        </button>

        <!-- Notification Trigger -->
        <div ref="notifWrapperRef" class="notifications-wrapper">
          <button
            type="button"
            class="header-icon-btn"
            :class="{ active: showNotifications }"
            title="Notifications"
            aria-label="View notifications"
            :aria-expanded="showNotifications"
            @click="toggleNotifications"
          >
            <Bell :size="17" />
            <span v-if="unreadCount > 0" class="notification-indicator-badge">
              {{ unreadCount > 9 ? '9+' : unreadCount }}
            </span>
          </button>

          <!-- Notification Dropdown -->
          <div v-if="showNotifications" class="notifications-dropdown">
            <div class="notifications-header">
              <div>
                <strong>Notifications</strong>
                <span v-if="unreadCount > 0" class="unread-pill">{{ unreadCount }} new</span>
              </div>
              <button
                v-if="unreadCount > 0"
                type="button"
                class="mark-all-read-btn"
                @click="handleMarkAllRead"
              >
                Mark all read
              </button>
            </div>
            <div class="notifications-list">
              <div v-if="userNotifications.length === 0" style="padding: 20px; text-align: center; color: #64748b; font-size: 0.82rem;">
                No notifications right now.
              </div>

              <div
                v-for="notif in userNotifications"
                :key="notif.id"
                :class="['notification-item', { unread: !notif.read }]"
                @click="handleNotificationClick(notif)"
              >
                <div :class="['notif-icon', notif.type === 'payment_received' ? 'success' : notif.type === 'maintenance_update' ? 'warning' : 'info']">
                  <CreditCard v-if="notif.type === 'payment_received'" :size="14" />
                  <Wrench v-else-if="notif.type === 'maintenance_update'" :size="14" />
                  <ShieldCheck v-else :size="14" />
                </div>
                <div class="notif-text">
                  <div style="display: flex; align-items: center; justify-content: space-between; gap: 6px;">
                    <strong>{{ notif.title }}</strong>
                    <span v-if="!notif.read" class="unread-dot"></span>
                  </div>
                  <p>{{ notif.message }}</p>
                  <small>{{ formatHumanDateTime(notif.timestamp) }}</small>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Far-Right Mobile/Tablet Menu Toggle Button -->
        <button
          type="button"
          class="menu-toggle"
          aria-label="Toggle navigation menu"
          @click="handleToggleSidebar"
        >
          <Menu :size="19" />
        </button>
      </div>
    </header>

    <!-- Expandable Search Bar directly beneath header (Click search icon to toggle open/close) -->
    <div v-if="isMobileSearchExpanded" class="mobile-search-bar-row">
      <div class="mobile-search-inner">
        <Search :size="16" style="color: #64748b; flex: none;" />
        <input
          ref="mobileSearchInput"
          v-model="store.searchQuery"
          type="text"
          placeholder="Search units, tenants, leases..."
          @keydown.esc="toggleMobileSearch"
        />
        <button type="button" class="mobile-search-close" title="Close search" @click="toggleMobileSearch">
          <X :size="16" />
        </button>
      </div>

      <!-- Live Search Results Dropdown -->
      <div v-if="store.searchQuery.trim()" class="search-dropdown-results">
        <div v-if="totalMatches === 0" class="search-no-results">
          No records matching "{{ store.searchQuery }}"
        </div>

        <div v-if="searchResults.units.length > 0" class="search-result-group">
          <div class="search-group-title">Units</div>
          <div
            v-for="u in searchResults.units"
            :key="u.id"
            class="search-result-item"
            @click="selectSearchResult(`/units/${u.id}`)"
          >
            <strong>Unit {{ u.unitNumber }}</strong>
            <span class="search-badge">{{ u.type }} · {{ u.status }}</span>
          </div>
        </div>

        <div v-if="searchResults.tenants.length > 0" class="search-result-group">
          <div class="search-group-title">Tenants</div>
          <div
            v-for="t in searchResults.tenants"
            :key="t.id"
            class="search-result-item"
            @click="selectSearchResult(`/tenants/${t.id}`)"
          >
            <strong>{{ t.name }}</strong>
            <span class="search-badge">{{ t.currentUnitNumber ? `Unit ${t.currentUnitNumber}` : 'Unassigned' }} · {{ t.phone }}</span>
          </div>
        </div>

        <div v-if="searchResults.leases.length > 0" class="search-result-group">
          <div class="search-group-title">Leases</div>
          <div
            v-for="l in searchResults.leases"
            :key="l.id"
            class="search-result-item"
            @click="selectSearchResult(`/leases/${l.id}`)"
          >
            <strong>{{ l.leaseNumber }}</strong>
            <span class="search-badge">{{ l.tenantName }} · Unit {{ l.unitNumber }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.header-wrapper {
  position: sticky;
  top: 0;
  z-index: 30;
  background: #ffffff;
}

.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: 56px;
  padding: 0 24px;
  border-bottom: 1px solid #e2e8f0;
  background: #ffffff;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 12px;
}

/* Mobile/Tablet Brand: Aligned Top-Left when sidebar drawer is collapsed */
.mobile-brand {
  display: none;
  align-items: center;
  gap: 10px;
  text-decoration: none;
  color: #0f172a;
}

.brand-mark {
  display: grid;
  place-items: center;
  width: 28px;
  height: 28px;
  border-radius: 6px;
  background: #2563eb;
  color: #ffffff;
  font-weight: 800;
  font-size: 13px;
  flex: none;
}

.mobile-brand-text {
  display: flex;
  flex-direction: column;
}

.mobile-brand-text strong {
  font-size: 0.95rem;
  font-weight: 700;
  letter-spacing: -0.2px;
  line-height: 1.1;
  color: #0f172a;
}

.mobile-brand-text small {
  font-size: 0.68rem;
  color: #64748b;
  font-weight: 500;
}

/* Desktop Page Title */
.desktop-page-title {
  display: inline-flex;
  align-items: center;
  min-width: 0;
}

.desktop-page-title h1 {
  margin: 0;
  font-family: "Google Sans Flex", "Google Sans", sans-serif;
  font-size: 1.02rem;
  font-weight: 700;
  letter-spacing: -0.015em;
  color: #0f172a;
  line-height: 1.2;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Header Right */
.header-right {
  display: flex;
  align-items: center;
  gap: 10px;
}

.header-icon-btn {
  position: relative;
  display: grid;
  place-items: center;
  width: 34px;
  height: 34px;
  border-radius: 6px;
  border: 1px solid #e2e8f0;
  background: #ffffff;
  color: #475467;
  cursor: pointer;
  transition: all 0.15s ease;
}

.header-icon-btn:hover,
.header-icon-btn.active {
  background: #f8fafc;
  color: #0f172a;
  border-color: #cbd5e1;
}

.notification-indicator {
  position: absolute;
  top: 6px;
  right: 6px;
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #2563eb;
  border: 1.5px solid #ffffff;
}

.menu-toggle {
  display: none;
  place-items: center;
  width: 36px;
  height: 36px;
  border: 1px solid #e2e8f0;
  background: #ffffff;
  color: #334155;
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.15s ease;
}

.menu-toggle:hover {
  background: #f1f5f9;
}

/* Dropdown */
.notifications-wrapper {
  position: relative;
}

.notifications-dropdown {
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  width: min(330px, calc(100vw - 24px));
  max-height: min(440px, 72vh);
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 10px;
  box-shadow: 0 12px 28px -6px rgba(15, 23, 42, 0.16);
  z-index: 60;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.notifications-header {
  padding: 10px 14px;
  background: #f8fafc;
  border-bottom: 1px solid #f1f5f9;
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex: none;
}

.notifications-header strong {
  font-size: 0.85rem;
  color: #0f172a;
}

.notifications-header small {
  font-size: 0.74rem;
  color: #64748b;
}

.notifications-list {
  padding: 6px;
  overflow-y: auto;
}

.notification-indicator-badge {
  position: absolute;
  top: -4px;
  right: -4px;
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  border-radius: 99px;
  background: #2563eb;
  color: #ffffff;
  font-size: 0.65rem;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid #ffffff;
}

.unread-pill {
  display: inline-block;
  margin-left: 6px;
  background: #eff6ff;
  color: #2563eb;
  padding: 1px 6px;
  border-radius: 99px;
  font-size: 0.7rem;
  font-weight: 600;
  border: 1px solid #bfdbfe;
}

.mark-all-read-btn {
  background: none;
  border: none;
  color: #2563eb;
  font-size: 0.74rem;
  font-weight: 600;
  cursor: pointer;
  padding: 0;
}

.mark-all-read-btn:hover {
  text-decoration: underline;
}

.notif-icon.warning {
  background: #fef3c7;
  color: #b45309;
}

.notification-item {
  display: flex;
  gap: 10px;
  padding: 10px;
  border-radius: 6px;
  cursor: pointer;
  transition: background 0.12s ease;
  position: relative;
}

.notification-item.unread {
  background: #f8fafc;
}

.notification-item:hover {
  background: #f1f5f9;
}

.unread-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: #2563eb;
  flex: none;
}

.notif-icon {
  display: grid;
  place-items: center;
  width: 26px;
  height: 26px;
  border-radius: 6px;
  flex: none;
}

.notif-icon.success {
  background: #dcfce7;
  color: #15803d;
}

.notif-icon.info {
  background: #dbeafe;
  color: #1d4ed8;
}

.notif-text {
  font-size: 0.8rem;
  line-height: 1.3;
}

.notif-text strong {
  display: block;
  color: #0f172a;
  font-size: 0.82rem;
}

.notif-text p {
  margin: 2px 0 0;
  color: #475467;
}

.notif-text small {
  display: block;
  margin-top: 4px;
  color: #94a3b8;
  font-size: 0.72rem;
}

@media (max-width: 1024px) {
  .header {
    padding: 0 16px;
    gap: 10px;
  }
  .header-left {
    min-width: 0;
    flex: 1;
  }
  .desktop-page-title {
    display: none;
  }
  .mobile-brand {
    display: flex;
    min-width: 0;
  }
  .header-right {
    flex: none;
    gap: 8px;
  }
  .menu-toggle {
    display: grid;
  }
}

@media (max-width: 520px) {
  .header {
    padding: 0 12px;
    gap: 8px;
  }
  .brand-mark {
    width: 28px;
    height: 28px;
    font-size: 0.8rem;
  }
  .mobile-brand {
    gap: 8px;
  }
  .mobile-brand-text strong {
    font-size: 0.86rem;
    letter-spacing: 0.055em;
  }
  .mobile-brand-text small {
    display: none;
  }
  .header-right {
    gap: 6px;
  }
  .notifications-dropdown {
    position: fixed;
    top: 62px;
    left: 12px;
    right: 12px;
    width: auto;
    max-width: 380px;
    margin-left: auto;
  }
}

.mobile-search-bar-row {
  background: #ffffff;
  border-bottom: 1px solid #e2e8f0;
  padding: 10px 16px;
  box-shadow: 0 4px 12px rgba(15, 23, 42, 0.08);
  animation: slideDown 0.15s ease-out;
}

.mobile-search-inner {
  display: flex;
  align-items: center;
  gap: 10px;
  background: #f8fafc;
  border: 1px solid #cbd5e1;
  border-radius: 8px;
  padding: 0 12px;
  height: 40px;
}

.mobile-search-inner input {
  width: 100%;
  border: 0;
  background: transparent;
  font: inherit;
  font-size: 0.88rem;
  outline: none;
  color: #0f172a;
}

.mobile-search-close {
  display: grid;
  place-items: center;
  border: 0;
  background: transparent;
  color: #64748b;
  cursor: pointer;
  padding: 4px;
}

.mobile-search-close:hover {
  color: #0f172a;
}

.search-dropdown-results {
  max-height: 280px;
  overflow-y: auto;
  margin-top: 10px;
  border-top: 1px solid #f1f5f9;
  padding-top: 8px;
}

.search-no-results {
  padding: 14px;
  text-align: center;
  color: #64748b;
  font-size: 0.82rem;
}

.search-result-group {
  margin-bottom: 8px;
}

.search-group-title {
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-weight: 700;
  color: #94a3b8;
  padding: 4px 8px;
}

.search-result-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 10px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 0.85rem;
  color: #0f172a;
  transition: background 0.12s ease;
}

.search-result-item:hover {
  background: #f1f5f9;
}

.search-badge {
  font-size: 0.75rem;
  color: #64748b;
}

@keyframes slideDown {
  from {
    transform: translateY(-8px);
    opacity: 0;
  }
  to {
    transform: translateY(0);
    opacity: 1;
  }
}
</style>
