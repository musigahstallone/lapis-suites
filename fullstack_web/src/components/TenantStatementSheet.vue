<script setup lang="ts">
import { computed } from 'vue'
import { Printer } from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import {
  store,
  formatKES,
  formatHumanDate,
  getTenantFinancialStanding,
  propertyInfo
} from '../data'
import type { Tenant } from '../types'

const props = defineProps<{
  open: boolean
  tenant: Tenant | null
}>()

const emit = defineEmits<{
  (e: 'close'): void
}>()

const activeLease = computed(() => {
  if (!props.tenant) return null
  return (
    store.leases.find(l => l.tenantId === props.tenant?.id && (l.status === 'active' || l.status === 'pending_deposit')) ||
    store.leases.find(l => l.tenantId === props.tenant?.id) ||
    null
  )
})

const currentUnit = computed(() => {
  if (!props.tenant?.currentUnitId) return null
  return store.units.find(u => u.id === props.tenant?.currentUnitId) || null
})

const standing = computed(() => getTenantFinancialStanding(props.tenant))

const tenantTransactions = computed(() => {
  if (!props.tenant) return []
  return store.transactions
    .filter(tx => tx.tenantId === props.tenant?.id && tx.status === 'reconciled')
    .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
})

interface StatementRow {
  date: string
  ref: string
  label: string
  billed: number
  paid: number
}

const statementRows = computed<StatementRow[]>(() => {
  if (!props.tenant) return []
  const rows: StatementRow[] = []
  const lease = activeLease.value
  const moveInDate = lease?.startDate || props.tenant.moveInDate || new Date().toISOString().slice(0, 10)
  const monthlyRent = lease?.monthlyRent || currentUnit.value?.monthlyRent || 0
  const depositReq = lease?.depositAmount || monthlyRent

  if (depositReq > 0) {
    rows.push({
      date: moveInDate,
      ref: `DEP-${props.tenant.currentUnitNumber || 'UNIT'}`,
      label: 'Security Deposit',
      billed: depositReq,
      paid: 0
    })
  }

  if (monthlyRent > 0) {
    rows.push({
      date: moveInDate,
      ref: `RENT-${moveInDate.slice(0, 7)}`,
      label: 'Monthly Rent',
      billed: monthlyRent,
      paid: 0
    })
  }

  for (const tx of tenantTransactions.value) {
    rows.push({
      date: tx.date,
      ref: tx.reference,
      label: tx.method === 'stk_push' ? 'M-Pesa STK Payment' : 'M-Pesa Payment',
      billed: 0,
      paid: tx.amount
    })
  }

  return rows
})

function handlePrint() {
  window.print()
}
</script>

<template>
  <SideSheet
    :open="open"
    :title="`Statement — ${tenant?.name || 'Resident'}`"
    subtitle="Account summary and payment history."
    width="680px"
    @close="emit('close')"
  >
    <div class="stmt-wrap">
      <!-- Clean Top Action Bar -->
      <div class="stmt-toolbar hide-on-print">
        <span class="stmt-date-note">{{ formatHumanDate(new Date().toISOString()) }}</span>
        <button type="button" class="primary-button" style="padding: 7px 14px; font-size: 0.82rem;" @click="handlePrint">
          <Printer :size="14" />
          <span>Print / Save PDF</span>
        </button>
      </div>

      <!-- Minimal Printable Statement -->
      <div id="printable-statement" class="stmt-doc">
        <!-- Header -->
        <header class="stmt-header">
          <div class="stmt-brand">
            <span class="stmt-mark">L</span>
            <div>
              <h2>{{ propertyInfo.name }}</h2>
              <p>{{ propertyInfo.city }}</p>
            </div>
          </div>
          <div class="stmt-ref-block">
            <span class="stmt-kicker">STATEMENT</span>
            <strong class="mono">#{{ tenant?.id?.slice(-6)?.toUpperCase() || '000000' }}</strong>
          </div>
        </header>

        <!-- Resident & Unit Line -->
        <section class="stmt-meta-row">
          <div>
            <small>Resident</small>
            <strong>{{ tenant?.name }}</strong>
            <span>{{ tenant?.phone }}</span>
          </div>
          <div>
            <small>Unit &amp; Rent</small>
            <strong>Unit {{ tenant?.currentUnitNumber || '—' }}</strong>
            <span>{{ formatKES(activeLease?.monthlyRent || currentUnit?.monthlyRent || 0) }}/month</span>
          </div>
          <div>
            <small>Next Due</small>
            <strong>{{ formatHumanDate(standing.nextDueDate) }}</strong>
            <span>{{ activeLease?.depositPaid ? 'Deposit Paid' : 'Deposit Pending' }}</span>
          </div>
        </section>

        <!-- 3 Simple KPI Numbers -->
        <section class="stmt-kpi-row">
          <div class="stmt-kpi">
            <span>Total Billed</span>
            <strong>{{ formatKES(standing.totalBilled) }}</strong>
          </div>
          <div class="stmt-kpi">
            <span>Total Paid</span>
            <strong class="positive">{{ formatKES(standing.totalPaid) }}</strong>
          </div>
          <div class="stmt-kpi">
            <span>{{ standing.balance > 0 ? 'Balance Due' : 'Account Credit' }}</span>
            <strong :class="standing.balance > 0 ? 'danger' : 'positive'">
              {{ standing.balance > 0 ? formatKES(standing.balance) : formatKES(standing.accountCredit) }}
            </strong>
          </div>
        </section>

        <!-- Clean Ledger Table -->
        <table class="stmt-table">
          <thead>
            <tr>
              <th>Date</th>
              <th>Reference</th>
              <th>Item</th>
              <th class="num">Billed</th>
              <th class="num">Paid</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="statementRows.length === 0">
              <td colspan="5" class="stmt-empty">No entries recorded yet.</td>
            </tr>
            <tr v-for="(row, idx) in statementRows" :key="idx">
              <td>{{ formatHumanDate(row.date) }}</td>
              <td class="cell-mono">{{ row.ref }}</td>
              <td>{{ row.label }}</td>
              <td class="num muted">{{ row.billed > 0 ? formatKES(row.billed) : '—' }}</td>
              <td class="num positive">{{ row.paid > 0 ? formatKES(row.paid) : '—' }}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr>
              <td colspan="3" class="num"><strong>Current Balance</strong></td>
              <td colspan="2" class="num">
                <strong :class="standing.balance > 0 ? 'danger' : 'positive'" style="font-size: 0.96rem;">
                  {{ standing.balance > 0 ? formatKES(standing.balance) : (standing.accountCredit > 0 ? `${formatKES(standing.accountCredit)} Credit` : 'KES 0') }}
                </strong>
              </td>
            </tr>
          </tfoot>
        </table>

        <!-- Minimal 1-Line Paybill Footer -->
        <footer class="stmt-footer">
          <span>Paybill <strong class="mono">{{ propertyInfo.paybillNumber }}</strong> · Account <strong class="mono">LAPIS-{{ tenant?.currentUnitNumber || 'UNIT' }}</strong></span>
          <span>{{ propertyInfo.name }}</span>
        </footer>
      </div>
    </div>
  </SideSheet>
</template>

<style scoped>
.stmt-wrap {
  padding: 2px 0;
}

.stmt-toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16px;
}

.stmt-date-note {
  font-size: 0.8rem;
  color: #64748b;
}

.stmt-doc {
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 10px;
  padding: 24px;
  color: #172033;
  font-family: inherit;
}

.stmt-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-bottom: 16px;
  border-bottom: 1px solid #e2e8f0;
  margin-bottom: 18px;
}

.stmt-brand {
  display: flex;
  align-items: center;
  gap: 10px;
}

.stmt-mark {
  width: 34px;
  height: 34px;
  border-radius: 8px;
  background: #111b35;
  color: #ffffff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-weight: 800;
  font-size: 1rem;
}

.stmt-brand h2 {
  font-size: 1rem;
  font-weight: 800;
  margin: 0;
  letter-spacing: 0.02em;
}

.stmt-brand p {
  font-size: 0.76rem;
  color: #64748b;
  margin: 2px 0 0;
}

.stmt-ref-block {
  text-align: right;
}

.stmt-kicker {
  display: block;
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  color: #64748b;
}

.stmt-ref-block strong {
  font-size: 0.9rem;
  color: #172033;
}

.stmt-meta-row {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 14px;
  margin-bottom: 18px;
}

.stmt-meta-row small {
  display: block;
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: #64748b;
  font-weight: 600;
  margin-bottom: 3px;
}

.stmt-meta-row strong {
  display: block;
  font-size: 0.88rem;
  color: #172033;
}

.stmt-meta-row span {
  display: block;
  font-size: 0.76rem;
  color: #64748b;
  margin-top: 2px;
}

.stmt-kpi-row {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
  margin-bottom: 20px;
}

.stmt-kpi {
  padding: 12px 14px;
  border-radius: 8px;
  background: #f8fafc;
  border: 1px solid #e2e8f0;
}

.stmt-kpi span {
  display: block;
  font-size: 0.72rem;
  color: #64748b;
  font-weight: 600;
}

.stmt-kpi strong {
  display: block;
  font-size: 1.05rem;
  font-weight: 800;
  margin-top: 4px;
  color: #172033;
}

.positive {
  color: #059669 !important;
}

.danger {
  color: #b91c1c !important;
}

.muted {
  color: #475569;
}

.stmt-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.82rem;
  margin-bottom: 18px;
}

.stmt-table th {
  text-align: left;
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: #64748b;
  padding: 8px 8px;
  border-bottom: 1px solid #e2e8f0;
}

.stmt-table td {
  padding: 10px 8px;
  border-bottom: 1px solid #f1f5f9;
}

.stmt-table tfoot td {
  border-top: 1.5px solid #172033;
  border-bottom: none;
  padding-top: 12px;
}

.stmt-table .num {
  text-align: right;
  white-space: nowrap;
}

.cell-mono {
  font-family: "Google Sans Code", monospace;
  font-size: 0.76rem;
  color: #334155;
}

.stmt-empty {
  text-align: center;
  padding: 20px;
  color: #64748b;
}

.stmt-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding-top: 14px;
  border-top: 1px solid #e2e8f0;
  font-size: 0.76rem;
  color: #64748b;
}

@media (max-width: 600px) {
  .stmt-meta-row,
  .stmt-kpi-row {
    grid-template-columns: 1fr;
  }
}

@media print {
  .hide-on-print {
    display: none !important;
  }
  .stmt-doc {
    border: none;
    padding: 0;
  }
}
</style>
