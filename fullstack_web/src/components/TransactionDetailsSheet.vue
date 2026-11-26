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
</script>

<template>
  <SideSheet :open="open" title="Payment Details" :subtitle="transaction ? `Reference: ${transaction.reference}` : ''"
    @close="emit('close')">
    <div v-if="transaction" class="tx-details-content">
      <!-- Concise Amount & Status Header -->
      <div class="summary-box">
        <div>
          <span class="sub-label">Payment Amount</span>
          <div class="amount-display">{{ formatKES(transaction.amount) }}</div>
        </div>
        <div>
          <span v-if="transaction.status === 'reconciled'" class="badge paid">
            <CheckCircle2 :size="12" /> Reconciled
          </span>
          <span v-else class="badge overdue">
            <AlertTriangle :size="12" /> Unassigned
          </span>
        </div>
      </div>

      <!-- Specific Tenant and Unit Reconciled To -->
      <div class="section-card">
        <h3 class="section-header">
          <Building2 :size="15" />
          <span>Reconciled Tenancy</span>
        </h3>

        <div v-if="transaction.reconciled && transaction.tenantId" class="reconciled-grid">
          <div class="info-cell">
            <span class="cell-label">Reconciled Resident</span>
            <strong class="cell-value">{{ transaction.tenantName }}</strong>
          </div>

          <div class="info-cell">
            <span class="cell-label">Reconciled Unit</span>
            <strong class="cell-value">Unit {{ transaction.unitNumber }}</strong>
          </div>

          <div class="info-cell">
            <span class="cell-label">Payment Date</span>
            <span class="cell-value mono">{{ transaction.date }}</span>
          </div>

          <div class="info-cell">
            <span class="cell-label">Payment Channel</span>
            <span class="cell-value" style="text-transform: capitalize;">
              {{ transaction.method.replace('_', ' ') }}
            </span>
          </div>

          <div class="info-cell">
            <span class="cell-label">Payment Verification</span>
            <span class="cell-value">
              <span
                v-if="transaction.source === 'callback' || transaction.reconciledBy?.includes('Webhook') || transaction.method === 'stk_push'"
                class="badge"
                style="background: #ecfdf5; color: #047857; border: 1px solid #a7f3d0; font-size: 0.74rem;">
                ● Verified via M-Pesa
              </span>
              <span v-else class="badge"
                style="background: #f1f5f9; color: #475569; border: 1px solid #cbd5e1; font-size: 0.74rem;">
                ● Management Entry
              </span>
            </span>
          </div>
        </div>

        <div v-else class="unassigned-notice">
          <AlertTriangle :size="16" />
          <span>This payment has not yet been assigned to a tenant or unit.</span>
        </div>
      </div>

      <!-- Payment Receipt & Verification Details -->
      <div class="section-card">
        <h3 class="section-header">
          <FileText :size="15" />
          <span>Payment Receipt Details</span>
        </h3>

        <div v-if="callbackPayload" class="payload-table">
          <div class="payload-row">
            <span class="payload-key">Receipt Reference</span>
            <strong class="payload-val mono">{{ callbackPayload.TransID }}</strong>
          </div>

          <div class="payload-row">
            <span class="payload-key">Payer Mobile</span>
            <strong class="payload-val mono">{{ callbackPayload.MSISDN }}</strong>
          </div>

          <div class="payload-row">
            <span class="payload-key">Payer Name</span>
            <span class="payload-val">{{ callbackPayload.PayerName }}</span>
          </div>

          <div class="payload-row">
            <span class="payload-key">Account / Unit Ref</span>
            <span class="payload-val mono">{{ callbackPayload.BillRefNumber }}</span>
          </div>

          <div class="payload-row">
            <span class="payload-key">Amount Paid</span>
            <strong class="payload-val text-positive">{{ formatKES(callbackPayload.TransAmount) }}</strong>
          </div>

          <div class="payload-row">
            <span class="payload-key">Payment Date & Time</span>
            <span class="payload-val mono">{{ transaction.timestamp }}</span>
          </div>

          <div class="payload-row">
            <span class="payload-key">Payment Channel</span>
            <span class="payload-val mono">{{ callbackPayload.BusinessShortCode }}</span>
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
