<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import {
  FileText,
  Building2,
  Calendar,
  CheckCircle2,
  AlertCircle,
  TrendingUp,
  Search,
  RefreshCw,
  CreditCard,
  ShieldCheck,
  ArrowRight
} from 'lucide-vue-next'
import {
  store,
  formatKES,
  formatHumanDate,
  formatHumanDateTime,
  getTenantFinancialStanding,
  fetchDashboard
} from '../data'

onMounted(async () => {
  await fetchDashboard()
})

const isRefreshing = ref(false)
const filterType = ref<'all' | 'arrears' | 'credit' | 'deposit'>('all')
const searchQuery = ref('')

async function refreshData() {
  isRefreshing.value = true
  try {
    await fetchDashboard()
  } finally {
    isRefreshing.value = false
  }
}

// Compute dynamic, real-time audit reflections from the ledger
interface AuditReflection {
  id: string
  timestamp: string
  date: string
  tenantName: string
  tenantId: string
  unitNumber: string
  reference: string
  amount: number
  method: string
  type: 'deposit' | 'arrears' | 'credit' | 'current'
  narrative: string
  balanceFigure: number
  statusBadge: string
  badgeClass: string
}

const auditReflections = computed<AuditReflection[]>(() => {
  const list: AuditReflection[] = []

  // 1. Process all verified transactions
  for (const tx of store.transactions) {
    const tenant = store.tenants.find(t => t.id === tx.tenantId)
    const standing = tenant ? getTenantFinancialStanding(tenant) : null

    let type: 'deposit' | 'arrears' | 'credit' | 'current' = 'current'
    let narrative = ''
    let statusBadge = 'Reconciled'
    let badgeClass = 'paid'

    if (tx.paymentType === 'deposit' || tx.notes?.toLowerCase().includes('deposit')) {
      type = 'deposit'
      statusBadge = 'Deposit Satisfied'
      badgeClass = 'paid'
      narrative = `${tx.tenantName} remitted ${formatKES(tx.amount)} via ${tx.method === 'stk_push' ? 'M-Pesa STK' : 'M-Pesa Paybill'} (${tx.reference}) allocated to Unit ${tx.unitNumber} Security Deposit. Contractual deposit requirement fulfilled.`
    } else if (standing && standing.balance > 0) {
      type = 'arrears'
      statusBadge = `Arrears: ${formatKES(standing.balance)}`
      badgeClass = 'overdue'
      narrative = `${tx.tenantName} paid ${formatKES(tx.amount)} for Unit ${tx.unitNumber} via M-Pesa (${tx.reference}). Remaining tenancy arrears balance is ${formatKES(standing.balance)}.`
    } else if (standing && standing.accountCredit > 0) {
      type = 'credit'
      statusBadge = `Prepaid: ${formatKES(standing.accountCredit)}`
      badgeClass = 'positive'
      narrative = `${tx.tenantName} remitted ${formatKES(tx.amount)} for Unit ${tx.unitNumber} via M-Pesa (${tx.reference}). Tenancy holds ${formatKES(standing.accountCredit)} in prepaid credit. Next rent is due on ${formatHumanDate(standing.nextDueDate)}.`
    } else {
      type = 'current'
      statusBadge = 'Account Settled'
      badgeClass = 'paid'
      narrative = `${tx.tenantName} settled ${formatKES(tx.amount)} for Unit ${tx.unitNumber} (${tx.reference}). Account balance is completely current with zero arrears.`
    }

    list.push({
      id: tx.id,
      timestamp: tx.timestamp || `${tx.date} 12:00:00`,
      date: tx.date,
      tenantName: tx.tenantName,
      tenantId: tx.tenantId || '',
      unitNumber: tx.unitNumber,
      reference: tx.reference,
      amount: tx.amount,
      method: tx.method,
      type,
      narrative,
      balanceFigure: standing ? (standing.balance > 0 ? standing.balance : standing.accountCredit) : 0,
      statusBadge,
      badgeClass
    })
  }

  // Sort newest first
  return list.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
})

const filteredReflections = computed(() => {
  return auditReflections.value.filter(item => {
    const matchesType =
      filterType.value === 'all' ||
      item.type === filterType.value

    const q = searchQuery.value.trim().toLowerCase()
    const matchesSearch =
      !q ||
      item.tenantName.toLowerCase().includes(q) ||
      item.unitNumber.toLowerCase().includes(q) ||
      item.reference.toLowerCase().includes(q) ||
      item.narrative.toLowerCase().includes(q)

    return matchesType && matchesSearch
  })
})

const totalCollections = computed(() => {
  return store.transactions.reduce((sum, tx) => sum + (tx.amount || 0), 0)
})

const totalArrearsInPortfolio = computed(() => {
  return store.tenants.reduce((sum, t) => {
    const st = getTenantFinancialStanding(t)
    return sum + (st.balance || 0)
  }, 0)
})

const totalCreditInPortfolio = computed(() => {
  return store.tenants.reduce((sum, t) => {
    const st = getTenantFinancialStanding(t)
    return sum + (st.accountCredit || 0)
  }, 0)
})
</script>

<template>
  <div class="page-body">
    <!-- Header -->
    <header class="page-intro">
      <div>
        <p class="eyebrow">FINANCIAL AUDIT & REFLECTIONS</p>
        <h1>Ledger Reflections & Audit Trail</h1>
        <p>Continuous plain-narrative financial audit log reflecting payments, arrears adjustments, prepaid balances, and escrow satisfaction.</p>
      </div>

      <div class="intro-actions">
        <button
          type="button"
          class="secondary-button"
          :disabled="isRefreshing"
          @click="refreshData"
        >
          <RefreshCw :size="14" :class="{ 'animate-spin': isRefreshing }" />
          <span>{{ isRefreshing ? 'Refreshing...' : 'Refresh Reflections' }}</span>
        </button>
      </div>
    </header>

    <!-- Financial Portfolio Metrics -->
    <section class="stats-grid" style="margin-bottom: 24px;">
      <article class="stat-card">
        <div class="stat-label">Total Verified Collections</div>
        <div class="stat-value text-positive">
          {{ formatKES(totalCollections) }}
        </div>
        <div class="stat-trend positive">
          <span>Reconciled into bank escrow</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Total Outstanding Arrears</div>
        <div class="stat-value text-danger">
          {{ formatKES(totalArrearsInPortfolio) }}
        </div>
        <div class="stat-trend negative">
          <span>Cumulative portfolio debt</span>
        </div>
      </article>

      <article class="stat-card">
        <div class="stat-label">Total Prepaid Advance Credit</div>
        <div class="stat-value" style="color: #0284c7;">
          {{ formatKES(totalCreditInPortfolio) }}
        </div>
        <div class="stat-trend positive">
          <span>Advance paid by residents</span>
        </div>
      </article>
    </section>

    <!-- Reflections Feed Panel -->
    <section class="structured-panel">
      <div class="panel-header-bar" style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px;">
        <div class="panel-filter-pills">
          <button
            :class="['filter-pill', { active: filterType === 'all' }]"
            @click="filterType = 'all'"
          >
            All Reflections ({{ auditReflections.length }})
          </button>
          <button
            :class="['filter-pill', { active: filterType === 'arrears' }]"
            @click="filterType = 'arrears'"
          >
            With Arrears / Debt
          </button>
          <button
            :class="['filter-pill', { active: filterType === 'credit' }]"
            @click="filterType = 'credit'"
          >
            Prepaid Advance Credit
          </button>
          <button
            :class="['filter-pill', { active: filterType === 'deposit' }]"
            @click="filterType = 'deposit'"
          >
            Security Deposit Allocations
          </button>
        </div>

        <div class="page-search-bar" style="width: 240px; margin-left: auto;">
          <Search :size="15" class="search-icon" />
          <input v-model="searchQuery" placeholder="Filter audit entries..." />
        </div>
      </div>

      <!-- Feed of Narrative Reflections -->
      <div v-if="filteredReflections.length > 0" style="display: flex; flex-direction: column; divide-y: 1px solid #f1f5f9;">
        <div
          v-for="item in filteredReflections"
          :key="item.id"
          style="padding: 16px 20px; border-bottom: 1px solid #f1f5f9; display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; transition: background 0.15s ease;"
        >
          <!-- Left side: Narrative & Meta -->
          <div style="flex: 1;">
            <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 4px;">
              <span class="mono" style="font-size: 0.76rem; color: #64748b;">
                {{ formatHumanDateTime(item.timestamp) }}
              </span>
              <span class="badge occupied" style="font-size: 0.70rem; padding: 2px 7px;">
                Unit {{ item.unitNumber }}
              </span>
              <span class="mono" style="font-size: 0.74rem; font-weight: 600; color: #3b82f6;">
                {{ item.reference }}
              </span>
            </div>

            <p style="font-size: 0.88rem; color: #1e293b; margin: 0; line-height: 1.45; font-weight: 500;">
              {{ item.narrative }}
            </p>
          </div>

          <!-- Right side: Reflection Status Pill & Link -->
          <div style="display: flex; flex-direction: column; align-items: flex-end; gap: 6px; flex-shrink: 0;">
            <span :class="['badge', item.badgeClass]" style="font-size: 0.76rem; padding: 4px 10px; font-weight: 600;">
              ● {{ item.statusBadge }}
            </span>
            <router-link
              v-if="item.tenantId"
              :to="`/tenants/${item.tenantId}`"
              class="text-button"
              style="font-size: 0.76rem; color: #475569; display: inline-flex; align-items: center; gap: 3px;"
            >
              <span>Tenant Profile</span>
              <ArrowRight :size="12" />
            </router-link>
          </div>
        </div>
      </div>

      <div v-else style="padding: 40px; text-align: center; color: #64748b;">
        No ledger reflections matching the selected criteria.
      </div>
    </section>
  </div>
</template>
