<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import {
  Home,
  CircleDollarSign,
  TrendingUp,
  AlertTriangle,
  ArrowRightLeft,
  ChevronRight,
  Plus,
  Clock,
  ShieldAlert,
  ArrowRight,
  Activity,
  CheckCircle2
} from 'lucide-vue-next'
import {
  store,
  dashboardAnalytics,
  formatKES,
  formatHumanDate,
  formatHumanDateTime,
  getTenantFinancialStanding,
  fetchDashboard
} from '../data'
import TransactionDetailsSheet from '../components/TransactionDetailsSheet.vue'
import LoadingSkeleton from '../components/LoadingSkeleton.vue'
import type { Transaction } from '../types'

const emit = defineEmits<{
  (e: 'openAddUnit'): void
  (e: 'openTransfer', tenantId?: string): void
}>()

const router = useRouter()
const stats = dashboardAnalytics
const isLoading = ref(false)

onMounted(async () => {
  isLoading.value = true
  await fetchDashboard()
  isLoading.value = false
})

// Transaction details side sheet
const selectedTransaction = ref<Transaction | null>(null)
const isDetailsOpen = ref(false)

function openTransaction(tx: Transaction) {
  selectedTransaction.value = tx
  isDetailsOpen.value = true
}

const recentTransactions = computed(() => {
  return store.transactions.slice(0, 5)
})

const tenantsWithBalances = computed(() => {
  return store.tenants.filter(t => getTenantFinancialStanding(t).balance > 0)
})

const unallocatedTransactions = computed(() => {
  return store.transactions.filter(t => t.status === 'unassigned')
})

const unallocatedTotalAmount = computed(() => {
  return unallocatedTransactions.value.reduce((acc, t) => acc + (t.amount || 0), 0)
})

const expiringLeases = computed(() => {
  const now = new Date()
  const nowTime = now.getTime()
  return store.leases
    .filter(l => l.status === 'active' && l.endDate)
    .map(l => {
      const end = new Date(l.endDate)
      const diffDays = Math.ceil((end.getTime() - nowTime) / (1000 * 60 * 60 * 24))
      return {
        ...l,
        diffDays
      }
    })
    .filter(l => l.diffDays >= 0 && l.diffDays <= 90)
    .sort((a, b) => a.diffDays - b.diffDays)
})

const collectionRate = computed(() => {
  const target = stats.monthlyRecurringRevenue
  if (!target || target <= 0) return 0
  const rate = Math.round((stats.currentMonthCollections / target) * 100)
  return Math.min(rate, 100)
})
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <p class="eyebrow">PORTFOLIO OVERVIEW</p>
        <h1>Dashboard</h1>
        <p>Real-time occupancy rates, monthly recurring revenue, and collections.</p>
      </div>

      <div class="intro-actions">
        <button class="secondary-button" @click="emit('openTransfer')">
          <ArrowRightLeft :size="15" />
          <span>Transfer Unit</span>
        </button>
        <button class="primary-button" @click="emit('openAddUnit')">
          <Plus :size="15" />
          <span>Add Unit</span>
        </button>
      </div>
    </header>

    <!-- Operational Status Banner: Unallocated Bank Transfers -->
    <div v-if="unallocatedTransactions.length > 0" class="reconciliation-status-banner">
      <div class="banner-left">
        <div class="banner-icon">
          <AlertTriangle :size="18" />
        </div>
        <div class="banner-content">
          <strong>{{ unallocatedTransactions.length }} Unallocated Bank Transfer(s) Awaiting Reconciliation</strong>
          <p>Totaling {{ formatKES(unallocatedTotalAmount) }} in suspense. Match these payments to resident ledgers to keep account balances accurate.</p>
        </div>
      </div>
      <router-link to="/reconciliation" class="banner-action-btn">
        <span>Review Queue</span>
        <ArrowRight :size="14" />
      </router-link>
    </div>

    <!-- Loading Skeleton while initial portfolio data loads -->
    <LoadingSkeleton v-if="isLoading && store.units.length === 0 && store.tenants.length === 0" variant="dashboard" :rows="4" />

    <!-- KPI Metric Cards (Strict 60-30-10 Palette: Calm White Cards, Uniform Neutral Slate Badges, High-Contrast Figures) -->
    <section v-else class="stats-grid">
      <!-- 1. Occupancy Rate -->
      <article class="stat-card">
        <div class="stat-header">
          <span class="stat-label">Occupancy Rate</span>
          <div class="stat-icon">
            <Home :size="15" />
          </div>
        </div>
        <div class="stat-value">{{ stats.occupancyRate }}%</div>
        <div class="stat-sub">
          <span>{{ stats.occupiedUnits }} of {{ stats.totalUnits }} units occupied</span>
        </div>
      </article>

      <!-- 2. Monthly Recurring Revenue -->
      <article class="stat-card">
        <div class="stat-header">
          <span class="stat-label">Monthly Recurring Revenue</span>
          <div class="stat-icon">
            <CircleDollarSign :size="15" />
          </div>
        </div>
        <div class="stat-value">{{ formatKES(stats.monthlyRecurringRevenue) }}</div>
        <div class="stat-sub">
          <span>{{ formatKES(stats.totalPotentialRevenue) }} potential</span>
        </div>
      </article>

      <!-- 3. Pending Collections -->
      <article class="stat-card">
        <div class="stat-header">
          <span class="stat-label">Pending Collections</span>
          <div class="stat-icon" :class="{ 'stat-icon-amber': stats.pendingCollections > 0 }">
            <AlertTriangle :size="15" />
          </div>
        </div>
        <div class="stat-value" :class="{ 'val-amber': stats.pendingCollections > 0 }">
          {{ formatKES(stats.pendingCollections) }}
        </div>
        <div class="stat-sub">
          <span>{{ tenantsWithBalances.length }} resident(s) pending</span>
        </div>
      </article>

      <!-- 4. Month Collections -->
      <article class="stat-card">
        <div class="stat-header">
          <span class="stat-label">Month Collections</span>
          <div class="stat-icon" :class="{ 'stat-icon-emerald': stats.currentMonthCollections > 0 }">
            <TrendingUp :size="15" />
          </div>
        </div>
        <div class="stat-value" :class="{ 'val-emerald': stats.currentMonthCollections > 0 }">
          {{ formatKES(stats.currentMonthCollections) }}
        </div>
        <div class="stat-sub">
          <span>Reconciled this month</span>
        </div>
      </article>
    </section>

    <!-- Operational Insights: Cash Flow Momentum & Lease Expiry Watchlist -->
    <section class="operational-insights-grid">
      <!-- Collection Trend Indicator & Cash Flow Momentum -->
      <article class="insight-card">
        <div class="insight-header">
          <div class="insight-title-group">
            <Activity :size="15" style="color: #64748b;" />
            <h3>Cash Flow Momentum</h3>
          </div>
          <span class="unit-type-pill" style="font-weight: 700;">{{ collectionRate }}% Realized</span>
        </div>
        <div class="momentum-meter">
          <div class="meter-track">
            <div class="progress-bar-unified" :style="{ width: `${collectionRate}%` }"></div>
          </div>
          <div class="meter-labels">
            <span>Collected: <strong style="color: #0f172a;">{{ formatKES(stats.currentMonthCollections) }}</strong></span>
            <span>Target MRR: <strong style="color: #0f172a;">{{ formatKES(stats.monthlyRecurringRevenue) }}</strong></span>
          </div>
        </div>
        <p style="margin: 10px 0 0 0; font-size: 0.76rem; color: #64748b;">
          <span v-if="collectionRate >= 90" style="color: #059669; font-weight: 600;">✓ Optimal Collection Velocity: High month-to-date realization.</span>
          <span v-else-if="collectionRate >= 50" style="color: #2563eb; font-weight: 600;">⚡ Stable Momentum: Payments continuing to reconcile smoothly.</span>
          <span v-else-if="stats.monthlyRecurringRevenue > 0" style="color: #b45309; font-weight: 600;">⏱ Early Billing Window: Rent collections underway.</span>
          <span v-else style="color: #94a3b8;">Awaiting active tenant leases to track monthly collection momentum.</span>
        </p>
      </article>

      <!-- Leases Expiring Within 30 to 90 Days Alert Widget -->
      <article class="insight-card">
        <div class="insight-header">
          <div class="insight-title-group">
            <Clock :size="15" style="color: #64748b;" />
            <h3>Lease Expiry Watchlist</h3>
          </div>
          <span :class="['unit-type-pill', expiringLeases.length > 0 ? 'badge pending' : '']">
            {{ expiringLeases.length }} Upcoming (30–90 Days)
          </span>
        </div>

        <div v-if="expiringLeases.length > 0" class="expiry-list">
          <div v-for="lease in expiringLeases" :key="lease.id" class="expiry-item">
            <div class="expiry-item-left">
              <span class="badge occupied">Unit {{ lease.unitNumber }}</span>
              <strong style="color: #0f172a;">{{ lease.tenantName }}</strong>
            </div>
            <div style="display: flex; align-items: center; gap: 8px;">
              <span style="font-size: 0.76rem; color: #64748b;">{{ formatHumanDate(lease.endDate) }}</span>
              <span :class="['expiry-days-badge', lease.diffDays <= 30 ? '' : 'warning']">
                {{ lease.diffDays <= 0 ? 'Expires today' : `${lease.diffDays}d left` }}
              </span>
            </div>
          </div>
        </div>
        <div v-else style="padding: 14px; text-align: center; background: #f8fafc; border-radius: 6px; border: 1px dashed var(--border-color); color: #64748b; font-size: 0.8rem;">
          <CheckCircle2 :size="15" style="color: #059669; vertical-align: middle; margin-right: 5px;" />
          <span>All leases active and healthy. No expirations within 90 days.</span>
        </div>
      </article>
    </section>

    <!-- Unit-Type Breakdown -->
    <section class="analytics-section">
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px;">
        <h2 style="font-size: 1.05rem; font-weight: 700; color: #0f172a;">Units Performance by Type</h2>
        <router-link to="/units" class="text-button" style="font-size: 0.8rem; color: #2563eb; display: inline-flex; align-items: center; gap: 4px;">
          View all units <ChevronRight :size="13" />
        </router-link>
      </div>

      <!-- Wide Balanced Horizontal Layout matching Units Inventory -->
      <div v-if="stats.breakdowns && stats.breakdowns.length > 0" class="unit-performance-cards-stack">
        <template v-for="b in stats.breakdowns" :key="b.type">
          <!-- Active Unit Category (Has units) -->
          <div v-if="b.totalCount > 0" class="unit-breakdown-card-wide">
            <div class="ub-meta-col">
              <div style="display: flex; align-items: center; gap: 8px;">
                <span class="unit-type-pill">{{ b.title }}</span>
                <strong class="ub-rate-badge">{{ b.occupancyRate }}% Occupancy</strong>
              </div>
              <div class="ub-rent-sub">
                <span>Baseline Rent:</span>
                <strong class="mono">{{ formatKES(b.avgRent) }}/mo</strong>
              </div>
            </div>

            <div class="ub-progress-col">
              <div class="progress-track" style="margin: 0; height: 6px;">
                <div
                  class="progress-bar-unified"
                  :style="{ width: `${b.occupancyRate}%` }"
                ></div>
              </div>
              <div class="ub-submetrics-row">
                <span>Occupied: <strong>{{ b.occupiedCount }} of {{ b.totalCount }} units</strong></span>
                <span>Available: <strong>{{ b.totalCount - b.occupiedCount }} vacant</strong></span>
              </div>
            </div>

            <div class="ub-revenue-col">
              <span class="ub-rev-label">Active Revenue</span>
              <strong class="ub-rev-val">{{ formatKES(b.activeRevenue) }}</strong>
            </div>
          </div>

          <!-- Polished Zero-State Card (When category has 0 units) -->
          <div v-else class="unit-breakdown-card-empty">
            <div style="display: flex; align-items: center; gap: 10px;">
              <span class="unit-type-pill">{{ b.title }}</span>
              <span class="empty-unit-note">0 units registered in this category</span>
            </div>
            <div style="display: flex; align-items: center; gap: 12px;">
              <span class="mono" style="font-size: 0.78rem; color: #94a3b8;">Baseline: {{ formatKES(b.avgRent) }}/mo</span>
              <button type="button" class="inline-add-btn" @click="emit('openAddUnit')">
                <Plus :size="12" /> Add {{ b.title }}
              </button>
            </div>
          </div>
        </template>
      </div>
      <div v-else style="padding: 24px 16px; text-align: center; background: #fff; border: 1px dashed var(--border-color); border-radius: 8px; color: #64748b; font-size: 0.88rem;">
        <p style="margin: 0 0 10px 0; font-weight: 500;">No units configured in your portfolio yet.</p>
        <button class="primary-button" style="margin: 0 auto; font-size: 0.82rem; padding: 6px 14px;" @click="emit('openAddUnit')">
          <Plus :size="14" /> Add Your First Unit
        </button>
      </div>
    </section>

    <!-- Structured List Group: Recent Payments -->
    <section class="structured-panel">
      <div class="panel-header-bar">
        <div class="panel-header-title">
          <h2>Recent Payment Transactions</h2>
          <p>Verified resident receipts and ledger entries. Click any row for details.</p>
        </div>
        <router-link to="/payments" class="text-button" style="font-size: 0.82rem;">
          View all <ChevronRight :size="14" />
        </router-link>
      </div>

      <!-- Responsive Table Wrapper for Tablet & Small Laptop Containment -->
      <div class="table-responsive-wrapper">
        <!-- Desktop List Header: Unit Name, Tenant Name, Date, Amount, Status (Single header, hidden <= 800px) -->
        <div class="list-group-header dashboard-payments-grid hide-mobile">
          <span>Unit Name</span>
          <span>Tenant Name</span>
          <span>Date</span>
          <span>Amount</span>
          <span style="text-align: right;">Reconciliation Status</span>
        </div>

        <div
          v-for="tx in recentTransactions"
          :key="tx.id"
          class="list-group-row interactive-row"
          style="cursor: pointer;"
          @click="openTransaction(tx)"
        >
          <!-- Desktop Row Display (Single Horizontal Line with Ellipsis Protection) -->
          <div class="dashboard-payments-grid hide-mobile">
            <div class="list-cell">
              <span class="badge occupied">Unit {{ tx.unitNumber }}</span>
            </div>

            <div class="list-cell">
              <strong style="color: #0f172a; font-size: 0.88rem;">{{ tx.tenantName }}</strong>
            </div>

            <div class="list-cell">
              <span class="mono" style="font-size: 0.84rem; color: #475467;">{{ formatHumanDate(tx.date) }}</span>
            </div>

            <div class="list-cell">
              <strong style="color: #059669; font-size: 0.92rem;">{{ formatKES(tx.amount) }}</strong>
            </div>

            <div class="list-cell" style="justify-content: flex-end;">
              <span :class="['badge', tx.status]">● {{ tx.status === 'reconciled' ? 'Reconciled' : 'Unassigned' }}</span>
            </div>
          </div>

          <!-- Mobile Card Display: Full Tenant Name top-left, Unit badge beside, humanized date bottom-left; Bold KES top-right, status underneath -->
          <div class="tx-card-mobile show-mobile-only">
            <div class="tx-card-left">
              <div class="tx-card-top-row">
                <strong class="tx-card-tenant">{{ tx.tenantName }}</strong>
                <span class="badge occupied">Unit {{ tx.unitNumber }}</span>
              </div>
              <span class="tx-card-time">{{ formatHumanDateTime(tx.timestamp || tx.date) }}</span>
            </div>

            <div class="tx-card-right">
              <strong class="tx-card-amount">{{ formatKES(tx.amount) }}</strong>
              <span :class="['badge', tx.status]">● {{ tx.status === 'reconciled' ? 'Reconciled' : 'Unassigned' }}</span>
            </div>
          </div>
        </div>

        <!-- Clean Zero-State without distracting heavy borders -->
        <div v-if="recentTransactions.length === 0" class="empty-transactions-container">
          <div class="empty-icon-circle">
            <CircleDollarSign :size="18" />
          </div>
          <p class="empty-title">No transactions recorded yet</p>
          <small class="empty-sub">Incoming M-Pesa payments and manual records will appear here in real time.</small>
        </div>
      </div>
    </section>

    <!-- Full uncollapsed transaction details sheet -->
    <TransactionDetailsSheet
      :open="isDetailsOpen"
      :transaction="selectedTransaction"
      @close="isDetailsOpen = false"
    />
  </div>
</template>
