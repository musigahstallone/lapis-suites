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
  fetchDashboard,
  fetchAuditLogs,
  type AuditLogEntry
} from '../data'

const activeTab = ref<'reflections' | 'system'>('reflections')
const systemLogs = ref<AuditLogEntry[]>([])

async function loadSystemLogs() {
  try {
    systemLogs.value = await fetchAuditLogs({ limit: 150 })
  } catch {
    systemLogs.value = []
  }
}

onMounted(async () => {
  await Promise.all([fetchDashboard(), loadSystemLogs()])
})

const isRefreshing = ref(false)
const filterType = ref<'all' | 'arrears' | 'credit' | 'deposit'>('all')
const searchQuery = ref('')

async function refreshData() {
  isRefreshing.value = true
  try {
    await Promise.all([fetchDashboard(), loadSystemLogs()])
  } finally {
    isRefreshing.value = false
  }
}

const filteredSystemLogs = computed(() => {
  const q = searchQuery.value.trim().toLowerCase()
  if (!q) return systemLogs.value
  return systemLogs.value.filter(entry =>
    entry.summary.toLowerCase().includes(q) ||
    entry.action.toLowerCase().includes(q) ||
    entry.actorName.toLowerCase().includes(q) ||
    entry.actorEmail.toLowerCase().includes(q) ||
    entry.entityType.toLowerCase().includes(q)
  )
})

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

    <!-- Reflections / System Audit Feed Panel -->
    <section class="structured-panel">
      <div class="panel-header-bar" style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px;">
        <div class="panel-filter-pills">
          <button
            :class="['filter-pill', { active: activeTab === 'reflections' }]"
            @click="activeTab = 'reflections'"
          >
            Ledger Reflections ({{ auditReflections.length }})
          </button>
          <button
            :class="['filter-pill', { active: activeTab === 'system' }]"
            @click="activeTab = 'system'"
          >
            Admin &amp; System Audit Log ({{ systemLogs.length }})
          </button>
        </div>

        <div class="page-search-bar" style="width: 240px; margin-left: auto;">
          <Search :size="15" class="search-icon" />
          <input v-model="searchQuery" placeholder="Filter audit entries..." />
        </div>
      </div>

      <div v-if="activeTab === 'reflections'" class="panel-header-bar" style="border-top: 1px solid #f1f5f9; padding-top: 10px; padding-bottom: 10px;">
        <div class="panel-filter-pills">
          <button :class="['filter-pill', { active: filterType === 'all' }]" @click="filterType = 'all'">All</button>
          <button :class="['filter-pill', { active: filterType === 'arrears' }]" @click="filterType = 'arrears'">With Arrears</button>
          <button :class="['filter-pill', { active: filterType === 'credit' }]" @click="filterType = 'credit'">Prepaid Credit</button>
          <button :class="['filter-pill', { active: filterType === 'deposit' }]" @click="filterType = 'deposit'">Deposits</button>
        </div>
      </div>

      <!-- Tab 1: Narrative Reflections -->
      <template v-if="activeTab === 'reflections'">
        <div v-if="filteredReflections.length > 0" style="display: flex; flex-direction: column;">
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
      </template>

      <!-- Tab 2: Persistent Admin & System Audit Log -->
      <template v-else>
        <div v-if="filteredSystemLogs.length > 0" style="display: flex; flex-direction: column;">
          <div
            v-for="entry in filteredSystemLogs"
            :key="entry.id"
            style="padding: 14px 20px; border-bottom: 1px solid #f1f5f9; display: flex; align-items: flex-start; justify-content: space-between; gap: 16px;"
          >
            <div style="flex: 1;">
              <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 4px; flex-wrap: wrap;">
                <span class="mono" style="font-size: 0.75rem; color: #64748b;">
                  {{ formatHumanDateTime(entry.timestamp) }}
                </span>
                <span class="badge occupied" style="font-size: 0.69rem; padding: 2px 7px; text-transform: uppercase;">
                  {{ entry.entityType }}
                </span>
                <span class="mono" style="font-size: 0.73rem; font-weight: 600; color: #0f172a;">
                  {{ entry.action }}
                </span>
              </div>
              <p style="font-size: 0.87rem; color: #1e293b; margin: 0; line-height: 1.45; font-weight: 500;">
                {{ entry.summary }}
              </p>
            </div>
            <div style="text-align: right; flex-shrink: 0;">
              <div style="font-size: 0.8rem; font-weight: 600; color: #0f172a;">{{ entry.actorName }}</div>
              <div style="font-size: 0.72rem; color: #64748b;">{{ entry.actorEmail }}</div>
            </div>
          </div>
        </div>
        <div v-else style="padding: 40px; text-align: center; color: #64748b;">
          No admin audit log entries recorded yet. Actions like payments, reconciliations, lease changes, and adjustments will appear here automatically.
        </div>
      </template>
    </section>
  </div>
</template>
