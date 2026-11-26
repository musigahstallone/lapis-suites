<script setup lang="ts">
import { ref, computed, watch, onUnmounted, nextTick } from 'vue'
import { Smartphone, CheckCircle2, AlertCircle, RefreshCw, ShieldCheck, RotateCw } from 'lucide-vue-next'
import SideSheet from './SideSheet.vue'
import SearchableSelect from './SearchableSelect.vue'
import PhoneInput from './PhoneInput.vue'
import {
  store,
  requestAdminStkOtp,
  verifyAndDispatchAdminStk,
  queryKcbStatus,
  formatKES,
  getTenantFinancialStanding,
  fetchPayments
} from '../data'
import { onKcbCallback, onPaymentReceived } from '../sse'

const props = defineProps<{
  open: boolean
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'success'): void
}>()

const selectedLeaseId = ref('')
const phoneNumber = ref('')
const amount = ref<number | ''>('')
const description = ref('Rent Payment')

// Admin OTP confirmation state
const otpStep = ref<'form' | 'otp' | 'waiting'>('form')
const challengeToken = ref('')
const adminMaskedPhone = ref('')
const otpDigits = ref<string[]>(['', '', '', '', '', ''])
const otpRefs = ref<(HTMLInputElement | null)[]>([])

const isSubmitting = ref(false)
const isCheckingStatus = ref(false)
const stkStatusText = ref('')
const error = ref('')
const successMessage = ref('')
const stkCheckoutRequestId = ref('')
const stkMerchantRequestId = ref('')

const otpCode = computed(() => otpDigits.value.join(''))
const isOtpComplete = computed(() => otpCode.value.length === 6 && /^\d{6}$/.test(otpCode.value))

const leaseOptions = computed(() => {
  return store.leases.map(l => {
    const tenant = store.tenants.find(t => t.id === l.tenantId)
    const standing = tenant ? getTenantFinancialStanding(tenant) : null
    const balanceText = standing && standing.balance > 0 ? ` · Arrears: ${formatKES(standing.balance)}` : ''
    return {
      value: l.id,
      label: `${l.tenantName} — Unit ${l.unitNumber}`,
      sublabel: `${tenant?.phone || 'No phone'} · Rent: ${formatKES(l.monthlyRent)}${balanceText}`
    }
  })
})

const tenantOptions = computed(() => {
  return store.tenants.map(t => {
    const standing = getTenantFinancialStanding(t)
    const balanceText = standing.balance > 0 ? ` · Arrears: ${formatKES(standing.balance)}` : ''
    return {
      value: t.id,
      label: `${t.name} (Unit ${t.currentUnitNumber || 'Unassigned'})`,
      sublabel: `${t.phone} · Balance: ${formatKES(standing.balance)}${balanceText}`
    }
  })
})

const targetOptions = computed(() => (leaseOptions.value.length > 0 ? leaseOptions.value : tenantOptions.value))

watch(selectedLeaseId, (leaseId) => {
  if (!leaseId) return
  const lease = store.leases.find(l => l.id === leaseId)
  if (lease) {
    const tenant = store.tenants.find(t => t.id === lease.tenantId)
    if (tenant?.phone) phoneNumber.value = tenant.phone
    const standing = tenant ? getTenantFinancialStanding(tenant) : null
    amount.value = standing && standing.balance > 0 ? standing.balance : lease.monthlyRent
    description.value = `Rent Payment Unit ${lease.unitNumber}`
  } else {
    const tenant = store.tenants.find(t => t.id === leaseId)
    if (tenant) {
      if (tenant.phone) phoneNumber.value = tenant.phone
      const standing = getTenantFinancialStanding(tenant)
      amount.value = standing.balance > 0 ? standing.balance : 0
      description.value = `Rent Payment Unit ${tenant.currentUnitNumber || 'Resident'}`
    }
  }
})

let unsubSseCallback: (() => void) | null = null
let unsubSsePayment: (() => void) | null = null

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      error.value = ''
      successMessage.value = ''
      otpStep.value = 'form'
      challengeToken.value = ''
      otpDigits.value = ['', '', '', '', '', '']
      isCheckingStatus.value = false
      if (targetOptions.value.length > 0 && !selectedLeaseId.value) {
        selectedLeaseId.value = targetOptions.value[0].value
      }

      if (!unsubSseCallback) {
        unsubSseCallback = onKcbCallback((data) => {
          const isTarget =
            (stkCheckoutRequestId.value && (data.checkoutRequestId === stkCheckoutRequestId.value || data.callback?.parsed?.checkoutRequestId === stkCheckoutRequestId.value)) ||
            (stkMerchantRequestId.value && (data.merchantRequestId === stkMerchantRequestId.value || data.callback?.parsed?.merchantRequestId === stkMerchantRequestId.value))

          if (isTarget && otpStep.value === 'waiting') {
            const isSuccess = data.status === 'Success' || data.callback?.parsed?.isSuccess
            if (isSuccess) {
              otpStep.value = 'form'
              successMessage.value = `Payment of ${formatKES(Number(amount.value))} confirmed via M-Pesa! Receipt: ${data.callback?.parsed?.mpesaReceiptNumber || 'Confirmed'}.`
              fetchPayments()
              emit('success')
              setTimeout(() => emit('close'), 2200)
            } else {
              otpStep.value = 'form'
              error.value = `Transaction declined: ${data.resultDesc || data.callback?.parsed?.resultDesc || 'Cancelled by user.'}`
            }
          }
        })
      }

      if (!unsubSsePayment) {
        unsubSsePayment = onPaymentReceived((data) => {
          if (otpStep.value === 'waiting' && data.transaction && data.transaction.phoneNumber === phoneNumber.value) {
            otpStep.value = 'form'
            successMessage.value = `Payment of ${formatKES(data.transaction.amount)} confirmed via M-Pesa! Receipt: ${data.transaction.reference}.`
            fetchPayments()
            emit('success')
            setTimeout(() => emit('close'), 2200)
          }
        })
      }
    } else {
      if (unsubSseCallback) { unsubSseCallback(); unsubSseCallback = null }
      if (unsubSsePayment) { unsubSsePayment(); unsubSsePayment = null }
    }
  }
)

onUnmounted(() => {
  if (unsubSseCallback) unsubSseCallback()
  if (unsubSsePayment) unsubSsePayment()
})

function handleDigitInput(idx: number, event: Event) {
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

function handleDigitKeydown(idx: number, event: KeyboardEvent) {
  if (event.key === 'Backspace') {
    if (otpDigits.value[idx]) otpDigits.value[idx] = ''
    else if (idx > 0) {
      otpDigits.value[idx - 1] = ''
      nextTick(() => otpRefs.value[idx - 1]?.focus())
    }
  }
}

function handlePaste(event: ClipboardEvent) {
  const pasted = (event.clipboardData?.getData('text') || '').replace(/\D/g, '').slice(0, 6)
  if (!pasted) return
  event.preventDefault()
  otpDigits.value = ['', '', '', '', '', '']
  pasted.split('').forEach((ch, i) => { otpDigits.value[i] = ch })
  nextTick(() => otpRefs.value[Math.min(pasted.length, 5)]?.focus())
}

async function handleRequestOtp() {
  error.value = ''
  successMessage.value = ''

  if (!phoneNumber.value || phoneNumber.value.replace(/\D/g, '').length < 9) {
    error.value = 'Please provide a valid Safaricom mobile phone number.'
    return
  }

  const amt = Number(amount.value)
  if (!amt || amt <= 0) {
    error.value = 'Please specify a valid payment amount (minimum KES 1).'
    return
  }

  const lease = store.leases.find(l => l.id === selectedLeaseId.value)
  const tenant = lease
    ? store.tenants.find(t => t.id === lease.tenantId)
    : store.tenants.find(t => t.id === selectedLeaseId.value)

  isSubmitting.value = true
  try {
    const res = await requestAdminStkOtp({
      amount: amt,
      unitNumber: lease?.unitNumber || tenant?.currentUnitNumber || '',
      tenantName: tenant?.name || lease?.tenantName || 'Resident'
    })
    challengeToken.value = res.challengeToken
    adminMaskedPhone.value = res.maskedPhone || ''
    otpDigits.value = ['', '', '', '', '', '']
    otpStep.value = 'otp'
    nextTick(() => otpRefs.value[0]?.focus())
  } catch (err: any) {
    error.value = err.message || 'Failed to send admin confirmation OTP.'
  } finally {
    isSubmitting.value = false
  }
}

async function handleVerifyAndDispatch() {
  error.value = ''
  if (!isOtpComplete.value) {
    error.value = 'Enter all 6 digits of your admin confirmation OTP.'
    return
  }

  const lease = store.leases.find(l => l.id === selectedLeaseId.value)
  const tenant = lease
    ? store.tenants.find(t => t.id === lease.tenantId)
    : store.tenants.find(t => t.id === selectedLeaseId.value)

  isSubmitting.value = true
  try {
    const res = await verifyAndDispatchAdminStk({
      challengeToken: challengeToken.value,
      code: otpCode.value,
      phoneNumber: phoneNumber.value,
      amount: Number(amount.value),
      invoiceNumber: `LAPIS-${lease?.unitNumber || tenant?.currentUnitNumber || 'RENT'}-${Date.now().toString().slice(-4)}`,
      description: description.value || 'Rent Payment',
      tenantId: tenant?.id,
      unitNumber: lease?.unitNumber || tenant?.currentUnitNumber
    })

    stkCheckoutRequestId.value = res.checkoutRequestId
    stkMerchantRequestId.value = res.merchantRequestId
    otpStep.value = 'waiting'
    stkStatusText.value = `Prompt sent to ${phoneNumber.value}. Awaiting resident M-Pesa PIN.`
  } catch (err: any) {
    error.value = err.message || 'Failed to verify OTP or dispatch STK Push.'
    otpDigits.value = ['', '', '', '', '', '']
    nextTick(() => otpRefs.value[0]?.focus())
  } finally {
    isSubmitting.value = false
  }
}

async function handleCheckStatusNow() {
  if (!stkCheckoutRequestId.value && !stkMerchantRequestId.value) return
  isCheckingStatus.value = true
  error.value = ''
  try {
    const queryRes = await queryKcbStatus(stkCheckoutRequestId.value, stkMerchantRequestId.value)
    if (queryRes.status === 'Success') {
      otpStep.value = 'form'
      successMessage.value = `Payment confirmed via M-Pesa! Receipt: ${queryRes.mpesaReceiptNumber || 'Confirmed'}.`
      await fetchPayments()
      emit('success')
      setTimeout(() => emit('close'), 2000)
    } else if (queryRes.status === 'Failed') {
      otpStep.value = 'form'
      error.value = `Transaction declined: ${queryRes.statusDescription || queryRes.resultDesc || 'Cancelled by user.'}`
    } else {
      stkStatusText.value = `Status is still pending (${queryRes.statusDescription || 'Waiting for PIN'}).`
    }
  } catch (err: any) {
    error.value = `Could not verify status: ${err.message || 'Network error'}`
  } finally {
    isCheckingStatus.value = false
  }
}
</script>

<template>
  <SideSheet
    :open="open"
    title="Initiate M-Pesa STK Push"
    subtitle="Requires 6-digit Admin SMS OTP confirmation before sending prompt to resident"
    width="520px"
    @close="emit('close')"
  >
    <div style="padding: 20px;">
      <div v-if="error" class="auth-alert error">
        <AlertCircle :size="16" class="auth-alert-icon" />
        <span>{{ error }}</span>
      </div>

      <div v-if="successMessage" class="auth-alert success">
        <CheckCircle2 :size="16" class="auth-alert-icon" />
        <span>{{ successMessage }}</span>
      </div>

      <!-- STEP 3: Awaiting PIN -->
      <div v-if="otpStep === 'waiting'" style="padding: 16px; background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px;">
        <div style="display: flex; align-items: center; justify-content: space-between; gap: 10px;">
          <div style="display: flex; align-items: center; gap: 8px;">
            <RefreshCw :size="16" class="animate-spin" style="color: #059669;" />
            <strong style="color: #0f172a; font-size: 0.9rem;">Prompt Dispatched to Resident</strong>
          </div>
          <button type="button" class="secondary-button" style="padding: 5px 12px; font-size: 0.78rem;" :disabled="isCheckingStatus" @click="handleCheckStatusNow">
            <RefreshCw :size="13" :class="{ 'animate-spin': isCheckingStatus }" />
            {{ isCheckingStatus ? 'Checking...' : 'Check Status' }}
          </button>
        </div>
        <p style="font-size: 0.82rem; color: #475467; margin-top: 8px;">{{ stkStatusText }}</p>
      </div>

      <!-- STEP 2: Admin OTP Verification -->
      <form v-else-if="otpStep === 'otp'" @submit.prevent="handleVerifyAndDispatch">
        <div style="padding: 12px 14px; background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px; margin-bottom: 16px; font-size: 0.82rem; color: #1e40af;">
          Confirm this STK Push of <strong>{{ formatKES(Number(amount || 0)) }}</strong> to <strong class="mono">{{ phoneNumber }}</strong> by entering the 6-digit SMS OTP sent to your admin phone <strong class="mono">{{ adminMaskedPhone }}</strong>.
        </div>

        <div class="otp-grid" style="margin-bottom: 18px;" @paste="handlePaste">
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
            @input="handleDigitInput(idx, $event)"
            @keydown="handleDigitKeydown(idx, $event)"
          />
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center; padding-top: 16px; border-top: 1px solid #eef2f6;">
          <button type="button" class="secondary-button" @click="otpStep = 'form'">Back</button>
          <div style="display: flex; gap: 8px;">
            <button type="button" class="secondary-button" :disabled="isSubmitting" @click="handleRequestOtp">
              <RotateCw :size="14" /> Resend
            </button>
            <button type="submit" class="primary-button" :disabled="isSubmitting || !isOtpComplete">
              <Smartphone :size="15" />
              <span>{{ isSubmitting ? 'Dispatching...' : 'Verify & Send STK' }}</span>
            </button>
          </div>
        </div>
      </form>

      <!-- STEP 1: Target & Amount Form -->
      <form v-else @submit.prevent="handleRequestOtp">
        <div class="form-field" style="margin-bottom: 16px;">
          <label>Select Target Agreement / Resident *</label>
          <SearchableSelect
            v-model="selectedLeaseId"
            :options="targetOptions"
            placeholder="Select lease or resident..."
            search-placeholder="Search by resident name, unit, or phone..."
          />
        </div>

        <div class="form-field" style="margin-bottom: 16px;">
          <label>Resident Safaricom M-Pesa Phone Number *</label>
          <PhoneInput v-model="phoneNumber" required placeholder="712345678" />
        </div>

        <div class="form-field" style="margin-bottom: 16px;">
          <label>Amount to Charge (KES) *</label>
          <input v-model="amount" type="number" min="1" required placeholder="e.g. 50000" />
        </div>

        <div class="form-field" style="margin-bottom: 20px;">
          <label>Payment Description</label>
          <input v-model="description" type="text" placeholder="e.g. Monthly Rent" />
        </div>

        <div style="display: flex; justify-content: flex-end; gap: 10px; padding-top: 16px; border-top: 1px solid #eef2f6;">
          <button type="button" class="secondary-button" @click="emit('close')">Cancel</button>
          <button type="submit" class="primary-button" :disabled="isSubmitting">
            <ShieldCheck :size="15" />
            <span>{{ isSubmitting ? 'Sending Admin OTP...' : 'Send Admin Confirmation OTP' }}</span>
          </button>
        </div>
      </form>
    </div>
  </SideSheet>
</template>
