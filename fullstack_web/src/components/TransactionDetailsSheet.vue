<script setup lang="ts">
import { ref, computed } from 'vue'
import {
  CreditCard,
  CheckCircle2,
  AlertTriangle,
  Building2,
  User,
  Phone,
  Calendar,
  Layers,
  FileCode,
  Printer,
  FileText
} from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import { formatKES, store, getTenantFinancialStanding } from '../data'
import { downloadReceiptPdf, printReceiptPdf } from '../utils/receiptGenerator'
import type { Transaction } from '../types'

const props = defineProps<{
  open: boolean
  transaction: Transaction | null
}>()

const emit = defineEmits<{
  (e: 'close'): void
}>()

const showRawPayload = ref(false)

const callbackPayload = computed(() => {
  const tx = props.transaction
  if (!tx) return null

  const raw = tx.rawCallback || {}
  const stk = raw?.Body?.stkCallback || raw?.stkCallback || raw || {}

  // Parse items from CallbackMetadata if STK Push
  let stkReceipt = ''
  let stkAmount: number | null = null
  let stkPhone = ''
  let stkDate = ''
  let stkBalance = ''

  const items = stk?.CallbackMetadata?.Item || stk?.callbackMetadata?.Item || stk?.CallbackMetadata?.item || []
  if (Array.isArray(items)) {
    for (const item of items) {
      const name = item.Name || item.name
      const val = item.Value !== undefined ? item.Value : item.value
      if (name === 'MpesaReceiptNumber') stkReceipt = String(val || '')
      if (name === 'Amount') stkAmount = Number(val || 0)
      if (name === 'PhoneNumber') stkPhone = String(val || '')
      if (name === 'TransactionDate') stkDate = String(val || '')
      if (name === 'Balance') stkBalance = String(val ?? '')
    }
  }

  const transId =
    stkReceipt ||
    raw.TransID ||
    raw.transID ||
    raw.transId ||
    tx.reference ||
    'N/A'

  const transAmount =
    stkAmount !== null
      ? stkAmount
      : (raw.TransAmount !== undefined ? Number(raw.TransAmount) : tx.amount)

  const msisdn =
    stkPhone ||
    raw.MSISDN ||
    raw.msisdn ||
    tx.phoneNumber ||
    'N/A'

  const firstName =
    raw.FirstName ||
    raw.firstName ||
    tx.payerName?.split(' ')[0] ||
    tx.tenantName?.split(' ')[0] ||
    'Remitter'

  const lastName =
    raw.LastName ||
    raw.lastName ||
    tx.payerName?.split(' ').slice(1).join(' ') ||
    tx.tenantName?.split(' ').slice(1).join(' ') ||
    ''

  const payerName =
    (raw.FirstName || raw.LastName)
      ? `${raw.FirstName || ''} ${raw.LastName || ''}`.trim()
      : (tx.payerName || tx.tenantName || 'Resident')

  const billRef =
    raw.BillRefNumber ||
    raw.billRefNumber ||
    tx.billRefNumber ||
    (tx.unitNumber ? `Unit ${tx.unitNumber}` : 'RENT')

  const shortCode =
    raw.BusinessShortCode ||
    raw.businessShortCode ||
    (tx.method === 'stk_push' ? 'KCB Buni Paybill (522522)' : '522522')

  const checkoutRequestId =
    stk?.CheckoutRequestID ||
    stk?.checkoutRequestId ||
    raw?.CheckoutRequestID ||
    raw?.checkoutRequestId ||
    ''

  const merchantRequestId =
    stk?.MerchantRequestID ||
    stk?.merchantRequestId ||
    raw?.MerchantRequestID ||
    raw?.merchantRequestId ||
    ''

  const resultDesc =
    stk?.ResultDesc ||
    stk?.resultDesc ||
    raw?.ResultDesc ||
    (tx.status === 'reconciled' ? 'The service request is processed successfully.' : '')

  return {
    TransID: transId,
    TransAmount: transAmount,
    MSISDN: msisdn,
    FirstName: firstName,
    LastName: lastName,
    PayerName: payerName,
    BillRefNumber: billRef,
    BusinessShortCode: shortCode,
    CheckoutRequestID: checkoutRequestId,
    MerchantRequestID: merchantRequestId,
    ResultDesc: resultDesc,
    HasRawJson: !!tx.rawCallback,
    FormattedRawJson: tx.rawCallback ? JSON.stringify(tx.rawCallback, null, 2) : ''
  }
})

function handleDownloadPdf() {
  if (!props.transaction) return
  const tenant = store.tenants.find(t => t.id === props.transaction?.tenantId) || null
  const lease = store.leases.find(l => l.id === props.transaction?.leaseId) || null
  const standing = tenant ? getTenantFinancialStanding(tenant) : null
  downloadReceiptPdf(props.transaction, tenant, lease, standing)
}

function handlePrintPdf() {
  if (!props.transaction) return
  const tenant = store.tenants.find(t => t.id === props.transaction?.tenantId) || null
  const lease = store.leases.find(l => l.id === props.transaction?.leaseId) || null
  const standing = tenant ? getTenantFinancialStanding(tenant) : null
  printReceiptPdf(props.transaction, tenant, lease, standing)
}
const formattedDateTime = computed(() => {
  const tx = props.transaction
  if (!tx) return '—'
  const raw = tx.timestamp || tx.date
  if (!raw) return '—'
  const d = new Date(raw.includes('T') ? raw : raw.replace(' ', 'T'))
  if (isNaN(d.getTime())) return raw
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
  const day = String(d.getDate()).padStart(2, '0')
  const hr24 = d.getHours()
  const ampm = hr24 >= 12 ? 'PM' : 'AM'
  const hr12 = String(hr24 % 12 || 12).padStart(2, '0')
  const min = String(d.getMinutes()).padStart(2, '0')
  return `${day} ${months[d.getMonth()]} ${d.getFullYear()} · ${hr12}:${min} ${ampm}`
})

const paymentChannelLabel = computed(() => {
  const m = (props.transaction?.method || '').toLowerCase()
  if (m.includes('stk')) return 'M-Pesa STK Push'
  if (m.includes('paybill')) return 'M-Pesa Paybill'
  if (m.includes('bank')) return 'Bank Transfer'
  if (m.includes('cash')) return 'Cash'
  return props.transaction?.method || 'M-Pesa'
})

const unitReferenceLabel = computed(() => {
  const tx = props.transaction
  if (!tx?.unitNumber) return '—'
  const unitObj = store.units.find(u => u.unitNumber === tx.unitNumber || u.id === tx.unitId)
  const leaseObj = store.leases.find(l => l.id === tx.leaseId || l.unitNumber === tx.unitNumber)
  const rawType = unitObj?.type || leaseObj?.unitType || ''
  const prettyType = rawType
    ? rawType.split(/[-_\s]+/).filter(Boolean).map((w: string) => w[0].toUpperCase() + w.slice(1).toLowerCase()).join(' ')
    : ''
  return prettyType ? `Unit ${tx.unitNumber} · ${prettyType}` : `Unit ${tx.unitNumber}`
})

const residentTitle = computed(() => {
  const tx = props.transaction
  return tx?.tenantName || tx?.payerName || 'Payment Receipt'
})
</script>

<template>
  <SideSheet :open="open" :title="residentTitle" :subtitle="transaction ? formatKES(transaction.amount) : ''"
    @close="emit('close')">
    <div v-if="transaction" class="tx-details-content">
      <!-- Clean Receipt Details -->
      <div class="section-card">
        <div v-if="callbackPayload" class="payload-table">
          <div class="payload-row">
            <span class="payload-key">M-Pesa Receipt</span>
            <strong class="payload-val mono">{{ callbackPayload.TransID }}</strong>
          </div>

          <div class="payload-row">
            <span class="payload-key">Date &amp; Time</span>
            <span class="payload-val">{{ formattedDateTime }}</span>
          </div>

          <div class="payload-row">
            <span class="payload-key">Payment Channel</span>
            <span class="payload-val">{{ paymentChannelLabel }}</span>
          </div>

          <div class="payload-row">
            <span class="payload-key">Unit Reference</span>
            <span class="payload-val">{{ unitReferenceLabel }}</span>
          </div>
        </div>

        <!-- Developer / Gateway Diagnostics (Visible ONLY to Landlord) -->
        <div
          v-if="store.session.role === 'landlord' && (callbackPayload?.CheckoutRequestID || callbackPayload?.HasRawJson)"
          style="margin-top: 14px; padding-top: 10px; border-top: 1px dashed #e2e8f0;">
          <button type="button" class="text-button"
            style="font-size: 0.75rem; font-weight: 600; color: #64748b; display: inline-flex; align-items: center; gap: 4px; background: none; border: none; cursor: pointer; padding: 0;"
            @click="showRawPayload = !showRawPayload">
            <FileCode :size="13" />
            <span>{{ showRawPayload ? 'Hide Technical Diagnostics' : 'Show Technical Gateway Diagnostics' }}</span>
          </button>

          <div v-if="showRawPayload" style="margin-top: 10px;">
            <div v-if="callbackPayload.CheckoutRequestID"
              style="font-size: 0.75rem; color: #64748b; margin-bottom: 4px;">
              Checkout ID: <span class="mono">{{ callbackPayload.CheckoutRequestID }}</span>
            </div>
            <div v-if="callbackPayload.MerchantRequestID"
              style="font-size: 0.75rem; color: #64748b; margin-bottom: 8px;">
              Merchant ID: <span class="mono">{{ callbackPayload.MerchantRequestID }}</span>
            </div>
            <pre v-if="callbackPayload.FormattedRawJson"
              style="padding: 10px; background: #0f172a; color: #38bdf8; border-radius: 6px; font-size: 0.70rem; overflow-x: auto; max-height: 180px; font-family: 'Google Sans Code', monospace;">{{ callbackPayload.FormattedRawJson }}</pre>
          </div>
        </div>
      </div>

      <!-- Action: Print / Save Official PDF Receipt -->
      <div class="no-print"
        style="margin-top: 10px; padding-top: 14px; border-top: 1px solid #eef2f6; display: flex; gap: 10px;">
        <button type="button" class="primary-button" style="flex: 1; justify-content: center; height: 38px; gap: 8px;"
          @click="handleDownloadPdf">
          <FileText :size="15" />
          <span>Download PDF Receipt</span>
        </button>
        <button type="button" class="secondary-button" style="justify-content: center; height: 38px; gap: 8px;"
          @click="handlePrintPdf">
          <Printer :size="15" />
          <span>Print</span>
        </button>
      </div>
    </div>
  </SideSheet>
</template>

<style scoped>
@media print {
  body * {
    visibility: hidden;
  }

  .tx-details-content,
  .tx-details-content * {
    visibility: visible;
  }

  .tx-details-content {
    position: absolute;
    left: 0;
    top: 0;
    width: 100%;
    padding: 24px;
    background: #ffffff !important;
  }

  .no-print {
    display: none !important;
  }
}

.tx-details-content {
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.summary-box {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px;
  background: #f8fafc;
  border-radius: 8px;
  border: 1px solid #e2e8f0;
}

.sub-label {
  display: block;
  font-size: 0.72rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: #64748b;
  margin-bottom: 2px;
}

.amount-display {
  font-size: 1.45rem;
  font-weight: 700;
  color: #059669;
}

.section-card {
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  padding: 16px;
}

.section-header {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 0.88rem;
  font-weight: 700;
  color: #0f172a;
  margin: 0 0 14px;
}

.reconciled-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.info-cell {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.cell-label {
  font-size: 0.72rem;
  font-weight: 600;
  color: #64748b;
  text-transform: uppercase;
}

.cell-value {
  font-size: 0.88rem;
  color: #0f172a;
}

.unassigned-notice {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px;
  background: #fffbeb;
  border: 1px solid #fef3c7;
  border-radius: 6px;
  color: #b45309;
  font-size: 0.84rem;
}

.payload-table {
  display: flex;
  flex-direction: column;
  border: 1px solid #f1f5f9;
  border-radius: 6px;
  overflow: hidden;
}

.payload-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 9px 12px;
  font-size: 0.82rem;
  border-bottom: 1px solid #f1f5f9;
}

.payload-row:last-child {
  border-bottom: 0;
}

.payload-row:nth-child(even) {
  background: #fcfcfd;
}

.payload-key {
  color: #64748b;
  font-weight: 500;
}

.payload-val {
  color: #0f172a;
  text-align: right;
}

.text-positive {
  color: #059669;
}
</style>
