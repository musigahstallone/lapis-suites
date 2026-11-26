<script setup lang="ts">
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import {
  ArrowLeft,
  CreditCard,
  Sparkles,
  CheckCircle2,
  AlertCircle,
  Smartphone,
  ShieldCheck,
  RefreshCw,
  RotateCw
} from 'lucide-vue-next'
import {
  store,
  processDirectPayment,
  formatKES,
  getTenantFinancialStanding,
  fetchTenants,
  fetchLeases,
  fetchUnits,
  fetchPayments,
  requestAdminStkOtp,
  verifyAndDispatchAdminStk,
  queryKcbStatus
} from '../data'
import { onKcbCallback, onPaymentReceived } from '../sse'
import SearchableSelect from '../components/SearchableSelect.vue'
import PhoneInput from '../components/PhoneInput.vue'
import { parseMpesaMessage, type ParsedMpesaMessage } from '../utils/mpesaParser'

const router = useRouter()

// Mode: Manual/Pasted SMS vs Admin OTP-Verified STK Push
const activeMode = ref<'manual' | 'stk'>('manual')

// Selection
const selectedLeaseId = ref('')
const selectedTenantId = ref('')
const amount = ref<number | ''>('')
const method = ref<'mpesa_paybill' | 'stk_push'>('mpesa_paybill')
const paymentDate = ref(new Date().toISOString().slice(0, 10))
const reference = ref('')
const notes = ref('')
const payerName = ref('')
const phoneNumber = ref('')
const error = ref('')
const isSubmitting = ref(false)

// M-Pesa SMS Extraction
const mpesaRawText = ref('')
const parseFeedback = ref<ParsedMpesaMessage | null>(null)
const parseError = ref('')

// Admin OTP-Verified STK Push State
const stkStep = ref<'prepare' | 'otp' | 'waiting' | 'done'>('prepare')
const adminOtpChallengeToken = ref('')
const adminMaskedPhone = ref('')
const otpDigits = ref<string[]>(['', '', '', '', '', ''])
const otpRefs = ref<(HTMLInputElement | null)[]>([])
const isRequestingAdminOtp = ref(false)
const isDispatchingStk = ref(false)
const isCheckingStk = ref(false)
const stkCheckoutRequestId = ref('')
const stkMerchantRequestId = ref('')
const stkStatusMessage = ref('')
const stkError = ref('')
const stkSuccess = ref('')

let unsubSseCallback: (() => void) | null = null
let unsubSsePayment: (() => void) | null = null

const otpCode = computed(() => otpDigits.value.join(''))
const isOtpComplete = computed(() => otpCode.value.length === 6 && /^\d{6}$/.test(otpCode.value))

onMounted(async () => {
  await Promise.all([fetchTenants(), fetchLeases(), fetchUnits()])
  if (store.leases.length > 0 && !selectedLeaseId.value) {
    selectedLeaseId.value = store.leases[0].id
  }

  unsubSseCallback = onKcbCallback((data) => {
    if (stkStep.value !== 'waiting') return
    const isTarget =
      (stkCheckoutRequestId.value && (data.checkoutRequestId === stkCheckoutRequestId.value || data.callback?.parsed?.checkoutRequestId === stkCheckoutRequestId.value)) ||
      (stkMerchantRequestId.value && (data.merchantRequestId === stkMerchantRequestId.value || data.callback?.parsed?.merchantRequestId === stkMerchantRequestId.value))

    if (isTarget) {
      const isSuccess = data.status === 'Success' || data.callback?.parsed?.isSuccess
      if (isSuccess) {
        stkStep.value = 'done'
        stkSuccess.value = `M-Pesa payment of ${formatKES(Number(amount.value || 0))} confirmed! Receipt: ${data.callback?.parsed?.mpesaReceiptNumber || data.mpesaReceiptNumber || 'Confirmed'}.`
        fetchPayments()
      } else {
        stkStep.value = 'prepare'
        stkError.value = `Transaction declined: ${data.resultDesc || data.callback?.parsed?.resultDesc || 'Cancelled by resident.'}`
      }
    }
  })

  unsubSsePayment = onPaymentReceived((data) => {
    if (stkStep.value !== 'waiting') return
    if (data.transaction && currentTenant.value && data.transaction.tenantId === currentTenant.value.id) {
      stkStep.value = 'done'
      stkSuccess.value = `M-Pesa payment of ${formatKES(data.transaction.amount)} confirmed! Receipt: ${data.transaction.reference}.`
      fetchPayments()
    }
  })
})

onUnmounted(() => {
  if (unsubSseCallback) unsubSseCallback()
  if (unsubSsePayment) unsubSsePayment()
})

const leaseOptions = computed(() => {
  return store.leases.map(l => {
    const tenant = store.tenants.find(t => t.id === l.tenantId)
    const standing = tenant ? getTenantFinancialStanding(tenant) : null
    const balanceText = standing && standing.balance > 0 ? ` · Arrears: ${formatKES(standing.balance)}` : ''
    return {
      value: l.id,
      label: `${l.tenantName} — Unit ${l.unitNumber}`,
      sublabel: `Lease ${l.leaseNumber} · ${formatKES(l.monthlyRent)}/mo · Unit ${l.unitNumber}${balanceText}`
    }
  })
})

const fallbackTenantOptions = computed(() => {
  return store.tenants.map(t => {
    const standing = getTenantFinancialStanding(t)
    const unitLabel = t.currentUnitNumber ? `Unit ${t.currentUnitNumber}` : 'No Unit Assigned'
    return {
      value: t.id,
      label: `${t.name} (${unitLabel})`,
      sublabel: `${t.phone} · Balance: ${formatKES(standing.balance)}`
    }
  })
})

const activeTargetOptions = computed(() => {
  if (leaseOptions.value.length > 0) return leaseOptions.value
  return fallbackTenantOptions.value
})

const currentLease = computed(() => {
  return store.leases.find(l => l.id === selectedLeaseId.value) || null
})

const currentTenant = computed(() => {
  if (currentLease.value) {
    return store.tenants.find(t => t.id === currentLease.value?.tenantId) || null
  }
  return store.tenants.find(t => t.id === selectedTenantId.value) || null
})

const currentStanding = computed(() => {
  return currentTenant.value ? getTenantFinancialStanding(currentTenant.value) : null
})

watch(selectedLeaseId, (leaseId) => {
  if (!leaseId) return
  const lease = store.leases.find(l => l.id === leaseId)
  if (lease) {
    selectedTenantId.value = lease.tenantId
    const tenant = store.tenants.find(t => t.id === lease.tenantId)
    if (tenant) {
      if (tenant.phone) phoneNumber.value = tenant.phone
      if (tenant.name) payerName.value = tenant.name
      const standing = getTenantFinancialStanding(tenant)
      amount.value = standing.balance > 0 ? standing.balance : lease.monthlyRent
    } else {
      amount.value = lease.monthlyRent
    }
    notes.value = `Rent payment for Unit ${lease.unitNumber}`
  }
})

function handleExtractMpesa() {
  parseError.value = ''
  parseFeedback.value = null

  if (!mpesaRawText.value.trim()) {
    parseError.value = 'Please paste an M-Pesa SMS message first.'
    return
  }

  const parsed = parseMpesaMessage(mpesaRawText.value)
  if (!parsed.success) {
    parseError.value = parsed.error || 'Failed to extract M-Pesa details. Please check the text format.'
    return
  }

  parseFeedback.value = parsed

  if (parsed.reference) reference.value = parsed.reference
  if (parsed.amount) amount.value = parsed.amount
  if (parsed.date) paymentDate.value = parsed.date
  if (parsed.phoneNumber) phoneNumber.value = parsed.phoneNumber
  if (parsed.payerName) payerName.value = parsed.payerName

  if (parsed.accountNumber) {
    const acc = parsed.accountNumber.toUpperCase()
    const matchedLease = store.leases.find(l => l.unitNumber.toUpperCase() === acc)
    if (matchedLease) {
      selectedLeaseId.value = matchedLease.id
    } else {
      const matchedTenant = store.tenants.find(t => t.currentUnitNumber.toUpperCase() === acc)
      if (matchedTenant) {
        const lease = store.leases.find(l => l.tenantId === matchedTenant.id)
        if (lease) selectedLeaseId.value = lease.id
        else selectedTenantId.value = matchedTenant.id
      }
    }
  } else if (parsed.phoneNumber) {
    const p = parsed.phoneNumber.slice(-9)
    const matchedTenant = store.tenants.find(t => t.phone && t.phone.includes(p))
    if (matchedTenant) {
      const lease = store.leases.find(l => l.tenantId === matchedTenant.id)
      if (lease) selectedLeaseId.value = lease.id
      else selectedTenantId.value = matchedTenant.id
    }
  }

  if (currentLease.value) {
    notes.value = `M-Pesa payment from ${parsed.payerName || 'Resident'} for Unit ${currentLease.value.unitNumber}`
  } else {
    notes.value = `M-Pesa payment from ${parsed.payerName || 'Resident'}`
  }
}

async function handleRecord() {
  error.value = ''
  const amt = Number(amount.value)
  if (!amt || amt <= 0) {
    error.value = 'Please enter a valid payment amount.'
    return
  }

  if (!selectedLeaseId.value && !selectedTenantId.value) {
    error.value = 'Please select the agreement or resident being paid for.'
    return
  }

  isSubmitting.value = true
  try {
    const lease = currentLease.value
    const tenant = currentTenant.value
    const unitId = lease?.unitId || tenant?.currentUnitId || undefined
    const unitNumber = lease?.unitNumber || tenant?.currentUnitNumber || ''

    await processDirectPayment({
      leaseId: lease?.id,
      tenantId: tenant?.id || lease?.tenantId,
      unitId,
      amount: amt,
      method: method.value,
      reference: reference.value || undefined,
      date: paymentDate.value,
      notes: notes.value || `Payment for Unit ${unitNumber}`,
      payerName: payerName.value || tenant?.name,
      phoneNumber: phoneNumber.value || tenant?.phone,
      source: 'manual',
      paymentType: 'deposit_and_rent'
    })

    router.push('/payments')
  } catch (e: any) {
    error.value = e?.message || 'Failed to record payment.'
    isSubmitting.value = false
  }
}

// --- Admin OTP-Verified STK Push Handlers ---
function handleOtpDigitInput(idx: number, event: Event) {
  const input = event.target as HTMLInputElement
  const raw = input.value.replace(/\D/g, '')
  if (raw.length > 1) {
    const chars = raw.slice(0, 6).split('')
    otpDigits.value = ['', '', '', '', '', '']
    chars.forEach((ch, i) => { otpDigits.value[i] = ch })
    nextTick(() => otpRefs.value[Math.min(chars.length, 5)]?.focus())
    return
  }
  otpDigits.value[idx] = raw
  if (raw && idx < 5) nextTick(() => otpRefs.value[idx + 1]?.focus())
}

function handleOtpDigitKeydown(idx: number, event: KeyboardEvent) {
  if (event.key === 'Backspace') {
    if (otpDigits.value[idx]) otpDigits.value[idx] = ''
    else if (idx > 0) {
      otpDigits.value[idx - 1] = ''
      nextTick(() => otpRefs.value[idx - 1]?.focus())
    }
  }
}

function handleOtpPaste(event: ClipboardEvent) {
  const pasted = (event.clipboardData?.getData('text') || '').replace(/\D/g, '').slice(0, 6)
  if (!pasted) return
  event.preventDefault()
  otpDigits.value = ['', '', '', '', '', '']
  pasted.split('').forEach((ch, i) => { otpDigits.value[i] = ch })
  nextTick(() => otpRefs.value[Math.min(pasted.length, 5)]?.focus())
}

async function handleRequestAdminOtpForStk() {
  stkError.value = ''
  stkSuccess.value = ''
  const amt = Number(amount.value)
  if (!amt || amt <= 0) {
    stkError.value = 'Enter a valid KES amount first.'
    return
  }
  if (!phoneNumber.value || phoneNumber.value.replace(/\D/g, '').length < 9) {
    stkError.value = 'Enter a valid resident Safaricom phone number first.'
    return
  }

  isRequestingAdminOtp.value = true
  try {
    const res = await requestAdminStkOtp({
      amount: amt,
      unitNumber: currentLease.value?.unitNumber || currentTenant.value?.currentUnitNumber || '',
      tenantName: currentTenant.value?.name || currentLease.value?.tenantName || 'Resident'
    })
    adminOtpChallengeToken.value = res.challengeToken
    adminMaskedPhone.value = res.maskedPhone || ''
    otpDigits.value = ['', '', '', '', '', '']
    stkStep.value = 'otp'
    nextTick(() => otpRefs.value[0]?.focus())
  } catch (err: any) {
    stkError.value = err.message || 'Failed to send confirmation OTP to your admin phone.'
  } finally {
    isRequestingAdminOtp.value = false
  }
}

async function handleVerifyOtpAndSendStk() {
  stkError.value = ''
  if (!isOtpComplete.value) {
    stkError.value = 'Please enter all 6 digits of the admin confirmation OTP.'
    return
  }

  isDispatchingStk.value = true
  try {
    const unitNum = currentLease.value?.unitNumber || currentTenant.value?.currentUnitNumber || 'RENT'
    const res = await verifyAndDispatchAdminStk({
      challengeToken: adminOtpChallengeToken.value,
      code: otpCode.value,
      phoneNumber: phoneNumber.value,
      amount: Math.round(Number(amount.value)),
      invoiceNumber: `LAPIS-${unitNum}-${Date.now().toString().slice(-4)}`,
      description: notes.value || `Rent Payment Unit ${unitNum}`,
      tenantId: currentTenant.value?.id || currentLease.value?.tenantId,
      unitNumber: unitNum
    })

    if (!res.success) {
      stkError.value = res.message || 'M-Pesa STK Push failed.'
      return
    }

    stkCheckoutRequestId.value = res.checkoutRequestId || ''
    stkMerchantRequestId.value = res.merchantRequestId || ''
    stkStatusMessage.value = `STK Push prompt sent to ${res.phoneNumber}. Waiting for resident to enter M-Pesa PIN...`
    stkStep.value = 'waiting'
  } catch (err: any) {
    stkError.value = err.message || 'OTP verification failed.'
    otpDigits.value = ['', '', '', '', '', '']
    nextTick(() => otpRefs.value[0]?.focus())
  } finally {
    isDispatchingStk.value = false
  }
}

async function handleCheckStkStatus() {
  if (!stkCheckoutRequestId.value && !stkMerchantRequestId.value) return
  isCheckingStk.value = true
  stkError.value = ''
  try {
    const q = await queryKcbStatus(stkCheckoutRequestId.value, stkMerchantRequestId.value)
    if (q.status === 'Success') {
      stkStep.value = 'done'
      stkSuccess.value = `Payment of ${formatKES(Number(q.amount || amount.value))} confirmed! M-Pesa Receipt: ${q.mpesaReceiptNumber || 'Confirmed'}.`
      await fetchPayments()
    } else if (q.status === 'Failed') {
      stkStep.value = 'prepare'
      stkError.value = `Transaction declined: ${q.resultDesc || q.statusDescription || 'Cancelled by resident.'}`
    } else {
      stkStatusMessage.value = 'Still awaiting resident PIN confirmation. Check again in a few seconds.'
    }
  } catch (err: any) {
    stkError.value = err.message || 'Could not query M-Pesa status.'
  } finally {
    isCheckingStk.value = false
  }
}
</script>

<template>
  <div class="page-body">
    <header class="page-intro">
      <div>
        <router-link to="/payments" class="text-button" style="margin-bottom: 8px; gap: 5px; display: inline-flex; align-items: center;">
          <ArrowLeft :size="15" /> Back to payments
        </router-link>
        <p class="eyebrow">PAYMENT RECORDING &amp; COLLECTION</p>
        <h1>Record Rent Payment</h1>
        <p>Log pasted M-Pesa confirmation SMS messages or dispatch an Admin OTP-verified M-Pesa STK Push directly to a resident.</p>
      </div>
    </header>

    <!-- Mode Switcher -->
    <div style="display: inline-flex; gap: 8px; margin-bottom: 20px; background: #f1f5f9; padding: 4px; border-radius: 8px; border: 1px solid #e2e8f0;">
      <button
        type="button"
        class="secondary-button"
        :style="activeMode === 'manual' ? 'background: #0f172a; color: white; border-color: #0f172a;' : 'background: transparent; border-color: transparent;'"
        @click="activeMode = 'manual'"
      >
        <Sparkles :size="14" />
        <span>Record / Paste M-Pesa SMS</span>
      </button>
      <button
        type="button"
        class="secondary-button"
        :style="activeMode === 'stk' ? 'background: #0f172a; color: white; border-color: #0f172a;' : 'background: transparent; border-color: transparent;'"
        @click="activeMode = 'stk'"
      >
        <Smartphone :size="14" />
        <span>Send M-Pesa STK Push (Admin OTP)</span>
      </button>
    </div>

    <!-- MODE 1: MANUAL / PASTE M-PESA SMS -->
    <div v-if="activeMode === 'manual'" style="display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 24px; max-width: 1040px; align-items: start;">
      <!-- LEFT COLUMN: M-Pesa SMS Message Parser Box -->
      <section class="panel" style="padding: 24px; border: 1px solid #e2e8f0; background: #ffffff;">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px;">
          <div style="display: flex; align-items: center; gap: 8px;">
            <Sparkles :size="18" style="color: #059669;" />
            <h2 style="font-size: 1.05rem; font-weight: 700; color: #0f172a; margin: 0;">M-Pesa SMS Parser</h2>
          </div>
          <span class="badge active" style="font-size: 0.72rem;">Notifies Resident Only</span>
        </div>

        <p style="font-size: 0.82rem; color: #64748b; margin-bottom: 14px;">
          Paste any Safaricom M-Pesa confirmation text to auto-extract receipt code, amount, date, and unit. Recording here texts the resident a receipt without texting the landlord.
        </p>

        <div class="form-field" style="margin-bottom: 12px;">
          <textarea
            v-model="mpesaRawText"
            rows="5"
            placeholder="Paste M-Pesa SMS here (e.g. 'QA12BC34DE Confirmed. Ksh15,000.00 sent to LAPIS SUITES for account 125F...')"
            style="width: 100%; padding: 10px 12px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 0.84rem; font-family: inherit; resize: vertical;"
          ></textarea>
        </div>

        <div style="display: flex; justify-content: flex-end; gap: 10px; margin-bottom: 16px;">
          <button
            type="button"
            class="secondary-button"
            style="display: inline-flex; align-items: center; gap: 6px; font-weight: 600;"
            @click="handleExtractMpesa"
          >
            <Sparkles :size="14" style="color: #059669;" />
            <span>Extract Details</span>
          </button>
        </div>

        <div v-if="parseError" style="padding: 10px 12px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.82rem; margin-bottom: 14px; display: flex; align-items: center; gap: 8px;">
          <AlertCircle :size="16" style="flex: none;" />
          <div>{{ parseError }}</div>
        </div>

        <div v-if="parseFeedback && parseFeedback.success" style="padding: 14px 16px; background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 8px; margin-bottom: 14px;">
          <div style="display: flex; align-items: center; gap: 6px; margin-bottom: 8px;">
            <CheckCircle2 :size="16" style="color: #059669;" />
            <strong style="font-size: 0.86rem; color: #166534;">Extracted Successfully</strong>
          </div>
          <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px; font-size: 0.80rem; color: #14532d;">
            <div><span>Code:</span> <span class="mono" style="font-weight: 700; margin-left: 4px;">{{ parseFeedback.reference || '—' }}</span></div>
            <div><span>Amount:</span> <strong style="margin-left: 4px;">{{ formatKES(parseFeedback.amount || 0) }}</strong></div>
            <div><span>Date:</span> <span style="margin-left: 4px;">{{ parseFeedback.date || '—' }} {{ parseFeedback.time }}</span></div>
            <div><span>Account:</span> <span style="margin-left: 4px; font-weight: 700;">{{ parseFeedback.accountNumber || '—' }}</span></div>
          </div>
        </div>

        <div v-if="currentLease" style="padding: 14px 16px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; margin-top: 16px;">
          <span style="font-size: 0.74rem; text-transform: uppercase; letter-spacing: 0.05em; color: #64748b; font-weight: 600;">
            Target Lease Agreement
          </span>
          <div style="display: flex; align-items: center; justify-content: space-between; margin-top: 4px;">
            <strong style="font-size: 0.95rem; color: #0f172a;">{{ currentLease.tenantName }}</strong>
            <span class="badge occupied">Unit {{ currentLease.unitNumber }}</span>
          </div>
          <div style="font-size: 0.80rem; color: #64748b; margin-top: 4px;">
            Lease <span class="mono">{{ currentLease.leaseNumber }}</span> · {{ formatKES(currentLease.monthlyRent) }}/mo
          </div>
          <div v-if="currentStanding" style="margin-top: 8px; font-size: 0.82rem;">
            <span :class="['badge', currentStanding.badgeClass]">{{ currentStanding.badgeText }}</span>
          </div>
        </div>
      </section>

      <!-- RIGHT COLUMN: Payment Details Form -->
      <section class="panel" style="padding: 24px; border: 1px solid #e2e8f0; background: #ffffff;">
        <h2 style="font-size: 1.05rem; font-weight: 700; color: #0f172a; margin-bottom: 14px;">Payment Details</h2>

        <form @submit.prevent="handleRecord">
          <div v-if="error" style="padding: 10px 12px; background: #fef2f2; border: 1px solid #fecaca; color: #b91c1c; border-radius: 6px; font-size: 0.82rem; margin-bottom: 16px;">
            {{ error }}
          </div>

          <div class="form-field" style="margin-bottom: 16px;">
            <label>Choose Lease Agreement / Resident *</label>
            <SearchableSelect
              v-model="selectedLeaseId"
              :options="activeTargetOptions"
              placeholder="Choose the lease being paid for..."
              search-placeholder="Search by resident name, unit number, or lease..."
            />
          </div>

          <div class="form-row" style="display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 16px;">
            <div class="form-field">
              <label>Amount (KES) *</label>
              <input v-model="amount" type="number" min="1" required placeholder="e.g. 50000" />
            </div>
            <div class="form-field">
              <label>Payment Method *</label>
              <select v-model="method">
                <option value="mpesa_paybill">Direct M-Pesa Paybill</option>
                <option value="stk_push">M-Pesa STK Push</option>
              </select>
            </div>
          </div>

          <div class="form-field" style="margin-bottom: 16px;">
            <label>Payment Date (Backdate Supported) *</label>
            <input v-model="paymentDate" type="date" required />
          </div>

          <div class="form-row" style="display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 16px;">
            <div class="form-field">
              <label>M-Pesa Receipt / Reference Code</label>
              <input v-model="reference" class="mono" placeholder="e.g. QA12BC34DE" />
            </div>
            <div class="form-field">
              <label>Sender Mobile Number</label>
              <PhoneInput v-model="phoneNumber" placeholder="712345678" />
            </div>
          </div>

          <div class="form-field" style="margin-bottom: 24px;">
            <label>Notes &amp; Description</label>
            <input v-model="notes" placeholder="e.g. Rent payment for Unit 125F" />
          </div>

          <div style="display: flex; justify-content: flex-end; gap: 10px; padding-top: 18px; border-top: 1px solid #eef2f6;">
            <router-link to="/payments" class="secondary-button">Cancel</router-link>
            <button type="submit" class="primary-button" :disabled="isSubmitting">
              <CreditCard :size="15" />
              <span>{{ isSubmitting ? 'Recording...' : 'Record Transaction' }}</span>
            </button>
          </div>
        </form>
      </section>
    </div>

    <!-- MODE 2: ADMIN OTP-VERIFIED M-PESA STK PUSH -->
    <div v-else style="max-width: 640px;">
      <section class="panel" style="padding: 24px; border: 1px solid #e2e8f0; background: #ffffff;">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
          <div style="display: flex; align-items: center; gap: 8px;">
            <ShieldCheck :size="19" style="color: #2563eb;" />
            <h2 style="font-size: 1.08rem; font-weight: 700; color: #0f172a; margin: 0;">Admin-Authorized M-Pesa STK Push</h2>
          </div>
          <span class="badge active" style="font-size: 0.72rem;">Admin OTP Required</span>
        </div>
        <p style="font-size: 0.83rem; color: #64748b; margin-bottom: 18px;">
          For security, you must first confirm a 6-digit SMS OTP sent to your administrator phone (configured in Settings) before dispatching an M-Pesa prompt to a resident.
        </p>

        <div v-if="stkError" class="auth-alert error">
          <AlertCircle :size="16" class="auth-alert-icon" />
          <span>{{ stkError }}</span>
        </div>

        <div v-if="stkSuccess" class="auth-alert success">
          <CheckCircle2 :size="16" class="auth-alert-icon" />
          <span>{{ stkSuccess }}</span>
        </div>

        <!-- Step 1: Select Resident, Phone, Amount -->
        <div v-if="stkStep === 'prepare'">
          <div class="form-field" style="margin-bottom: 14px;">
            <label>Target Resident / Lease *</label>
            <SearchableSelect
              v-model="selectedLeaseId"
              :options="activeTargetOptions"
              placeholder="Choose lease or resident..."
              search-placeholder="Search resident or unit..."
            />
          </div>

          <div class="form-row" style="display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 14px;">
            <div class="form-field">
              <label>Resident Safaricom Number *</label>
              <PhoneInput v-model="phoneNumber" required placeholder="712345678" />
            </div>
            <div class="form-field">
              <label>Amount to Request (KES) *</label>
              <input v-model="amount" type="number" min="1" required placeholder="e.g. 35000" />
            </div>
          </div>

          <div class="form-field" style="margin-bottom: 18px;">
            <label>Payment Description</label>
            <input v-model="notes" placeholder="e.g. Monthly Rent Payment" />
          </div>

          <div style="display: flex; justify-content: flex-end; gap: 10px; padding-top: 14px; border-top: 1px solid #eef2f6;">
            <router-link to="/payments" class="secondary-button">Cancel</router-link>
            <button
              type="button"
              class="primary-button"
              :disabled="isRequestingAdminOtp"
              @click="handleRequestAdminOtpForStk"
            >
              <ShieldCheck :size="15" />
              <span>{{ isRequestingAdminOtp ? 'Sending Admin OTP...' : 'Step 1: Send Confirmation OTP to My Phone' }}</span>
            </button>
          </div>
        </div>

        <!-- Step 2: Enter 6-Digit Admin OTP -->
        <form v-else-if="stkStep === 'otp'" @submit.prevent="handleVerifyOtpAndSendStk">
          <div style="padding: 12px 14px; background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px; margin-bottom: 16px; font-size: 0.83rem; color: #1e40af;">
            Enter the 6-digit OTP sent to your admin phone <strong class="mono">{{ adminMaskedPhone }}</strong> to authorize sending an M-Pesa STK Push of
            <strong>{{ formatKES(Number(amount || 0)) }}</strong> to <strong>{{ currentTenant?.name || 'Resident' }}</strong> (<span class="mono">{{ phoneNumber }}</span>).
          </div>

          <div class="otp-grid" style="margin-bottom: 18px;" @paste="handleOtpPaste">
            <input
              v-for="(_, idx) in otpDigits"
              :key="idx"
              :ref="(el) => { otpRefs[idx] = el as HTMLInputElement | null }"
              v-model="otpDigits[idx]"
              type="text"
              inputmode="numeric"
              maxlength="6"
              class="otp-digit"
              style="border: 1.5px solid #cbd5e1; border-radius: 8px; height: 48px; text-align: center; font-family: 'Google Sans Code', monospace; font-size: 1.3rem; font-weight: 700;"
              @input="handleOtpDigitInput(idx, $event)"
              @keydown="handleOtpDigitKeydown(idx, $event)"
            />
          </div>

          <div style="display: flex; justify-content: space-between; align-items: center; padding-top: 14px; border-top: 1px solid #eef2f6;">
            <button type="button" class="secondary-button" @click="stkStep = 'prepare'; stkError = ''">
              Back
            </button>
            <div style="display: flex; gap: 8px;">
              <button type="button" class="secondary-button" :disabled="isRequestingAdminOtp" @click="handleRequestAdminOtpForStk">
                <RotateCw :size="14" :class="{ 'animate-spin': isRequestingAdminOtp }" />
                <span>Resend OTP</span>
              </button>
              <button type="submit" class="primary-button" :disabled="isDispatchingStk || !isOtpComplete">
                <Smartphone :size="15" />
                <span>{{ isDispatchingStk ? 'Verifying & Dispatching...' : 'Verify OTP & Send STK Push' }}</span>
              </button>
            </div>
          </div>
        </form>

        <!-- Step 3: Waiting for Resident M-Pesa PIN -->
        <div v-else-if="stkStep === 'waiting'" style="padding: 20px; background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px; text-align: center;">
          <RefreshCw :size="24" class="animate-spin" style="color: #2563eb; margin-bottom: 10px;" />
          <h3 style="font-size: 1rem; margin-bottom: 6px;">M-Pesa Prompt Sent to Resident</h3>
          <p style="font-size: 0.84rem; color: #64748b; margin-bottom: 14px;">{{ stkStatusMessage }}</p>
          <div style="display: flex; gap: 8px; justify-content: center;">
            <button type="button" class="primary-button" :disabled="isCheckingStk" @click="handleCheckStkStatus">
              <RefreshCw :size="14" :class="{ 'animate-spin': isCheckingStk }" />
              <span>{{ isCheckingStk ? 'Checking...' : 'Check Status Now' }}</span>
            </button>
            <button type="button" class="secondary-button" @click="stkStep = 'prepare'">
              Start Another
            </button>
          </div>
        </div>

        <!-- Step 4: Confirmed -->
        <div v-else style="text-align: center; padding: 14px 0;">
          <CheckCircle2 :size="36" style="color: #059669; margin-bottom: 10px;" />
          <h3 style="margin-bottom: 6px;">Payment Confirmed &amp; Reconciled</h3>
          <p style="font-size: 0.85rem; color: #64748b; margin-bottom: 16px;">Both resident and landlord SMS confirmations have been triggered by the M-Pesa callback.</p>
          <div style="display: flex; gap: 10px; justify-content: center;">
            <router-link to="/payments" class="primary-button">View Payments Ledger</router-link>
            <button type="button" class="secondary-button" @click="stkStep = 'prepare'; stkSuccess = ''">Send Another STK Push</button>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
