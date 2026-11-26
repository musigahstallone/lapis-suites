<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import {
  Smartphone,
  ShieldCheck,
  AlertCircle,
  CheckCircle2,
  CreditCard,
  Clock,
  RotateCw,
  RefreshCw,
  ArrowLeft,
  Lock,
  Building2
} from 'lucide-vue-next'
import { formatKES, formatHumanDate } from '../data'
import { safeFetchJson } from '../utils/safeFetch'
import { onKcbCallback, onPaymentReceived } from '../sse'
import PhoneInput from '../components/PhoneInput.vue'

const route = useRoute()

const linkId = computed(() => String(route.params.linkId || '').trim())

type PayStep = 'phone' | 'otp' | 'pay' | 'receipt'
const step = ref<PayStep>('phone')

// Link preview (strictly non-sensitive: first name & unit number ONLY — never shows phone or paid banner)
const isLoadingLink = ref(false)
const linkPreview = ref<{
  linkId: string
  firstName: string
  unitNumber: string
  status: string
} | null>(null)
const linkError = ref('')

// Step 1: Phone Entry (+254 + 9 digits)
const phoneInput = ref('')
const isRequestingOtp = ref(false)

// Step 2: OTP Entry
const challengeToken = ref('')
const digits = ref<string[]>(['', '', '', '', '', ''])
const inputRefs = ref<(HTMLInputElement | null)[]>([])
const isVerifyingOtp = ref(false)
const isResendingOtp = ref(false)
const resendCooldown = ref(0)
const otpExpiresIn = ref(600)
let timerHandle: ReturnType<typeof setInterval> | null = null

// Step 3: Verified Tenant Arrears & STK Push
const paySessionToken = ref('')
const account = ref<{
  tenantId: string
  tenantName: string
  unitNumber: string
  phone: string
  leaseNumber: string
  monthlyRent: number
  depositAmount: number
  depositPaid: boolean
  balance: number
  arrearsBalance: number
  accountCredit: number
  nextPaymentDueDate: string
  recentPayments: Array<{ id: string; reference: string; amount: number; date: string; method: string; status: string }>
} | null>(null)

const payAmount = ref<number>(0)
const mpesaPhone = ref('')
const isInitiatingStk = ref(false)
const isAwaitingPin = ref(false)
const isCheckingStatus = ref(false)
const stkCheckoutRequestId = ref('')
const stkMerchantRequestId = ref('')
const stkStatusText = ref('')

// Step 4: Confirmed Receipt
const receiptInfo = ref<{
  amount: number
  receiptNumber: string
  remainingBalance: number
  accountCredit: number
} | null>(null)

const error = ref('')
const info = ref('')

let unsubSseCallback: (() => void) | null = null
let unsubSsePayment: (() => void) | null = null
let pollInterval: ReturnType<typeof setInterval> | null = null

const otpCode = computed(() => digits.value.join(''))
const isCodeComplete = computed(() => otpCode.value.length === 6 && /^\d{6}$/.test(otpCode.value))
const formattedExpiry = computed(() => {
  const secs = Math.max(0, otpExpiresIn.value)
  return `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`
})

onMounted(async () => {
  if (linkId.value) {
    await loadLinkPreview()
  }

  timerHandle = setInterval(() => {
    if (resendCooldown.value > 0) resendCooldown.value--
    if (step.value === 'otp' && otpExpiresIn.value > 0) otpExpiresIn.value--
  }, 1000)

  unsubSseCallback = onKcbCallback(async (data) => {
    if (!isAwaitingPin.value) return
    const isTarget =
      (stkCheckoutRequestId.value && (data.checkoutRequestId === stkCheckoutRequestId.value || data.callback?.parsed?.checkoutRequestId === stkCheckoutRequestId.value)) ||
      (stkMerchantRequestId.value && (data.merchantRequestId === stkMerchantRequestId.value || data.callback?.parsed?.merchantRequestId === stkMerchantRequestId.value))

    if (isTarget) {
      const isSuccess = data.status === 'Success' || data.callback?.parsed?.isSuccess
      if (isSuccess) {
        await handlePaymentConfirmed(
          data.callback?.parsed?.mpesaReceiptNumber || data.mpesaReceiptNumber || 'CONFIRMED',
          Number(data.callback?.parsed?.amount || data.amount || payAmount.value)
        )
      } else {
        stopStatusPolling()
        isAwaitingPin.value = false
        error.value = `M-Pesa payment declined: ${data.resultDesc || data.callback?.parsed?.resultDesc || 'Cancelled or timed out.'}`
      }
    }
  })

  unsubSsePayment = onPaymentReceived(async (data) => {
    if (!isAwaitingPin.value || !account.value) return
    if (data.transaction && (data.transaction.tenantId === account.value.tenantId || data.transaction.unitNumber === account.value.unitNumber)) {
      await handlePaymentConfirmed(data.transaction.reference || 'CONFIRMED', Number(data.transaction.amount || payAmount.value))
    }
  })
})

onUnmounted(() => {
  if (timerHandle) clearInterval(timerHandle)
  if (unsubSseCallback) unsubSseCallback()
  if (unsubSsePayment) unsubSsePayment()
  stopStatusPolling()
})

function stopStatusPolling() {
  if (pollInterval) {
    clearInterval(pollInterval)
    pollInterval = null
  }
}

async function loadLinkPreview() {
  isLoadingLink.value = true
  linkError.value = ''
  const res = await safeFetchJson(`/api/public-pay/link/${encodeURIComponent(linkId.value)}`)
  if (!res.ok) {
    linkError.value = res.error || 'This payment link is invalid or currently unavailable.'
  } else {
    linkPreview.value = res.data
  }
  isLoadingLink.value = false
}

async function handleRequestOtp() {
  error.value = ''
  info.value = ''
  if (!phoneInput.value || phoneInput.value.replace(/\D/g, '').length !== 12) {
    error.value = 'Please enter your 9-digit mobile phone number starting with 7 or 1.'
    return
  }

  isRequestingOtp.value = true
  const res = await safeFetchJson('/api/public-pay/request-otp', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      phone: phoneInput.value,
      linkId: linkId.value || undefined
    })
  })
  isRequestingOtp.value = false

  if (!res.ok) {
    error.value = res.error || 'Could not send verification SMS. Please try again.'
    return
  }

  challengeToken.value = res.data.challengeToken
  otpExpiresIn.value = res.data.expiresInSeconds || 600
  resendCooldown.value = 30
  digits.value = ['', '', '', '', '', '']
  step.value = 'otp'
  nextTick(() => inputRefs.value[0]?.focus())
}

function handleDigitInput(index: number, event: Event) {
  const input = event.target as HTMLInputElement
  const raw = input.value.replace(/\D/g, '')
  if (raw.length > 1) {
    const chars = raw.slice(0, 6).split('')
    digits.value = ['', '', '', '', '', '']
    chars.forEach((ch, idx) => { digits.value[idx] = ch })
    nextTick(() => inputRefs.value[Math.min(chars.length, 5)]?.focus())
    return
  }
  digits.value[index] = raw
  if (raw && index < 5) nextTick(() => inputRefs.value[index + 1]?.focus())
}

function handleDigitKeydown(index: number, event: KeyboardEvent) {
  if (event.key === 'Backspace') {
    if (digits.value[index]) {
      digits.value[index] = ''
    } else if (index > 0) {
      digits.value[index - 1] = ''
      nextTick(() => inputRefs.value[index - 1]?.focus())
    }
  } else if (event.key === 'ArrowLeft' && index > 0) {
    inputRefs.value[index - 1]?.focus()
  } else if (event.key === 'ArrowRight' && index < 5) {
    inputRefs.value[index + 1]?.focus()
  }
}

function handlePaste(event: ClipboardEvent) {
  const pasted = (event.clipboardData?.getData('text') || '').replace(/\D/g, '').slice(0, 6)
  if (!pasted) return
  event.preventDefault()
  digits.value = ['', '', '', '', '', '']
  pasted.split('').forEach((ch, idx) => { digits.value[idx] = ch })
  nextTick(() => inputRefs.value[Math.min(pasted.length, 5)]?.focus())
}

async function handleVerifyOtp() {
  error.value = ''
  info.value = ''
  if (!isCodeComplete.value) {
    error.value = 'Please enter all 6 digits of your SMS OTP.'
    return
  }

  isVerifyingOtp.value = true
  const res = await safeFetchJson('/api/public-pay/verify-otp', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      challengeToken: challengeToken.value,
      code: otpCode.value
    })
  })
  isVerifyingOtp.value = false

  if (!res.ok) {
    error.value = res.error || 'Verification code is invalid or expired.'
    digits.value = ['', '', '', '', '', '']
    nextTick(() => inputRefs.value[0]?.focus())
    return
  }

  paySessionToken.value = res.data.paySessionToken
  account.value = res.data.account
  payAmount.value = res.data.account.balance > 0 ? res.data.account.balance : res.data.account.monthlyRent
  mpesaPhone.value = res.data.account.phone || phoneInput.value
  step.value = 'pay'
}

async function handleResendOtp() {
  if (resendCooldown.value > 0 || isResendingOtp.value) return
  isResendingOtp.value = true
  error.value = ''
  info.value = ''

  const res = await safeFetchJson('/api/public-pay/request-otp', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      phone: phoneInput.value,
      linkId: linkId.value || undefined
    })
  })
  isResendingOtp.value = false

  if (!res.ok) {
    error.value = res.error || 'Failed to resend verification code.'
    return
  }
  challengeToken.value = res.data.challengeToken
  otpExpiresIn.value = res.data.expiresInSeconds || 600
  resendCooldown.value = 30
  digits.value = ['', '', '', '', '', '']
  info.value = 'A fresh 6-digit SMS OTP has been sent to your phone.'
  nextTick(() => inputRefs.value[0]?.focus())
}

async function handleStkPush() {
  error.value = ''
  info.value = ''
  if (!payAmount.value || Number(payAmount.value) <= 0) {
    error.value = 'Enter a valid payment amount greater than KES 0.'
    return
  }
  if (!mpesaPhone.value || mpesaPhone.value.replace(/\D/g, '').length !== 12) {
    error.value = 'Enter a valid 9-digit Safaricom M-Pesa number starting with 7 or 1.'
    return
  }

  isInitiatingStk.value = true
  const res = await safeFetchJson('/api/public-pay/stkpush', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${paySessionToken.value}`
    },
    body: JSON.stringify({
      amount: Math.round(Number(payAmount.value)),
      phoneNumber: mpesaPhone.value
    })
  })
  isInitiatingStk.value = false

  if (!res.ok || !res.data?.success) {
    error.value = res.error || res.data?.message || 'Failed to send M-Pesa STK Push prompt. Please try again.'
    return
  }

  stkCheckoutRequestId.value = res.data.checkoutRequestId || ''
  stkMerchantRequestId.value = res.data.merchantRequestId || ''
  stkStatusText.value = 'M-Pesa prompt sent to your phone. Enter your M-Pesa PIN to complete payment.'
  isAwaitingPin.value = true

  let polls = 0
  stopStatusPolling()
  pollInterval = setInterval(async () => {
    polls++
    if (polls > 15 || !isAwaitingPin.value) {
      stopStatusPolling()
      return
    }
    await checkPaymentStatus(true)
  }, 4000)
}

async function checkPaymentStatus(silent = false) {
  if (!stkCheckoutRequestId.value && !stkMerchantRequestId.value) return
  if (!silent) isCheckingStatus.value = true

  // Also triggers live KCB query if callback was delayed/missed
  const res = await safeFetchJson('/api/kcb/query', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${paySessionToken.value}`
    },
    body: JSON.stringify({
      checkoutRequestId: stkCheckoutRequestId.value,
      merchantRequestId: stkMerchantRequestId.value,
      syncLive: !silent
    })
  })

  if (!silent) isCheckingStatus.value = false
  if (!res.ok) {
    if (!silent) error.value = res.error || 'Could not check payment status right now.'
    return
  }

  const data = res.data
  if (data.status === 'Success') {
    await handlePaymentConfirmed(data.mpesaReceiptNumber || 'CONFIRMED', Number(data.amount || payAmount.value))
  } else if (data.status === 'Failed') {
    stopStatusPolling()
    isAwaitingPin.value = false
    error.value = `M-Pesa transaction declined: ${data.resultDesc || data.statusDescription || 'Cancelled by user.'}`
  } else if (!silent) {
    stkStatusText.value = 'Still awaiting M-Pesa confirmation. If you just entered your PIN, wait a few seconds and tap check again.'
  }
}

async function handlePaymentConfirmed(receiptNumber: string, amountPaid: number) {
  stopStatusPolling()
  isAwaitingPin.value = false

  let remaining = Math.max(0, (account.value?.balance || 0) - amountPaid)
  let credit = account.value?.accountCredit || 0

  const statusRes = await safeFetchJson('/api/public-pay/status', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${paySessionToken.value}`
    },
    body: JSON.stringify({
      checkoutRequestId: stkCheckoutRequestId.value,
      merchantRequestId: stkMerchantRequestId.value
    })
  })
  if (statusRes.ok && statusRes.data?.updatedStanding) {
    remaining = statusRes.data.updatedStanding.balance
    credit = statusRes.data.updatedStanding.accountCredit
  }

  receiptInfo.value = {
    amount: amountPaid,
    receiptNumber,
    remainingBalance: remaining,
    accountCredit: credit
  }
  step.value = 'receipt'
}
</script>

<template>
  <main class="auth-page">
    <aside class="auth-aside">
      <div class="brand">
        <span class="brand-mark">L</span>
        LAPIS SUITES
      </div>

      <div class="auth-copy">
        <p class="eyebrow">EXPRESS RENT PAYMENT</p>
        <h1>Verify your phone &amp; settle rent in seconds.</h1>
        <p>No password required. Confirm your mobile number with a one-time SMS code to view your private balance and pay directly via M-Pesa STK Push.</p>
      </div>

      <p class="quote">
        “Every payment link is private to your unit, protected by SMS OTP, and reconciled to your ledger automatically.”
        <small>— Lapis Suites Billing &amp; Reconciliation</small>
      </p>
    </aside>

    <section class="auth-main">
      <div class="login-card" style="width: min(460px, 100%);">
        <div class="mobile-brand">
          <span class="brand-mark">L</span>
          LAPIS SUITES
        </div>

        <div class="auth-steps" aria-label="Payment steps">
          <div :class="['auth-step', step === 'phone' ? 'active' : 'done']">
            <span>{{ step === 'phone' ? '1' : '✓' }}</span> Phone
          </div>
          <div :class="['auth-step-line', step !== 'phone' ? 'done' : '']"></div>
          <div :class="['auth-step', step === 'otp' ? 'active' : (step === 'pay' || step === 'receipt' ? 'done' : '')]">
            <span>{{ step === 'pay' || step === 'receipt' ? '✓' : '2' }}</span> SMS OTP
          </div>
          <div :class="['auth-step-line', step === 'pay' || step === 'receipt' ? 'done' : '']"></div>
          <div :class="['auth-step', step === 'pay' ? 'active' : (step === 'receipt' ? 'done' : '')]">
            <span>{{ step === 'receipt' ? '✓' : '3' }}</span> M-Pesa Pay
          </div>
        </div>

        <div v-if="isLoadingLink" class="auth-security-note" style="margin-bottom: 16px;">
          <RefreshCw :size="15" class="animate-spin" />
          <span>Loading your private payment link...</span>
        </div>

        <div v-if="linkError" class="auth-alert error">
          <AlertCircle :size="16" class="auth-alert-icon" />
          <span>{{ linkError }}</span>
        </div>

        <!-- STEP 1: PHONE IDENTITY VERIFICATION (No masked phone shown!) -->
        <form v-if="step === 'phone'" @submit.prevent="handleRequestOtp">
          <p class="eyebrow">
            {{ linkPreview ? `UNIT ${linkPreview.unitNumber} · PERSONAL PAY LINK` : 'STEP 1 OF 3 · IDENTITY CHECK' }}
          </p>
          <h1>{{ linkPreview ? `Hi ${linkPreview.firstName}, verify your phone` : 'Pay your rent' }}</h1>
          <p class="subtle">
            Enter your registered mobile number to receive an SMS OTP and view your balance.
          </p>

          <div v-if="error" class="auth-alert error">
            <AlertCircle :size="16" class="auth-alert-icon" />
            <span>{{ error }}</span>
          </div>

          <label>
            Registered Mobile Phone Number
            <PhoneInput
              v-model="phoneInput"
              required
              placeholder="712345678"
              :disabled="Boolean(linkError)"
            />
          </label>

          <div class="auth-security-note">
            <Lock :size="15" />
            <span>Your arrears and balance are private and only shown after confirming the 6-digit SMS code.</span>
          </div>

          <button type="submit" class="primary-button submit" :disabled="isRequestingOtp || Boolean(linkError)">
            <Smartphone :size="16" />
            <span>{{ isRequestingOtp ? 'Sending SMS OTP...' : 'Send 6-Digit SMS OTP' }}</span>
          </button>

          <div class="auth-footer-nav center">
            <router-link to="/login" class="text-button auth-inline-link">
              <ArrowLeft :size="15" />
              <span>Sign in to Resident Portal</span>
            </router-link>
          </div>
        </form>

        <!-- STEP 2: ENTER 6-DIGIT SMS OTP -->
        <form v-else-if="step === 'otp'" @submit.prevent="handleVerifyOtp">
          <p class="eyebrow">STEP 2 OF 3 · SMS VERIFICATION</p>
          <h1>Enter verification code</h1>
          <p class="subtle">
            Enter the 6-digit code sent via SMS to your registered mobile phone.
          </p>

          <div v-if="error" class="auth-alert error">
            <AlertCircle :size="16" class="auth-alert-icon" />
            <span>{{ error }}</span>
          </div>

          <div v-if="info" class="auth-alert success">
            <CheckCircle2 :size="16" class="auth-alert-icon" />
            <span>{{ info }}</span>
          </div>

          <div class="otp-header-row">
            <span class="otp-label">
              <Smartphone :size="14" />
              6-Digit OTP Code
            </span>
            <span :class="['otp-timer', { expired: otpExpiresIn === 0 }]">
              <Clock :size="13" />
              {{ otpExpiresIn > 0 ? `Expires in ${formattedExpiry}` : 'Code expired' }}
            </span>
          </div>

          <div class="otp-grid" @paste="handlePaste">
            <input
              v-for="(_, idx) in digits"
              :key="idx"
              :ref="(el) => { inputRefs[idx] = el as HTMLInputElement | null }"
              v-model="digits[idx]"
              type="text"
              inputmode="numeric"
              autocomplete="one-time-code"
              maxlength="6"
              class="otp-digit"
              :aria-label="`OTP digit ${idx + 1}`"
              @input="handleDigitInput(idx, $event)"
              @keydown="handleDigitKeydown(idx, $event)"
            />
          </div>

          <button type="submit" class="primary-button submit" :disabled="isVerifyingOtp || !isCodeComplete">
            <ShieldCheck :size="16" />
            <span>{{ isVerifyingOtp ? 'Verifying...' : 'Verify & View My Balance' }}</span>
          </button>

          <div class="auth-footer-nav between">
            <button type="button" class="text-button auth-inline-link" @click="step = 'phone'; error = ''; info = ''">
              <ArrowLeft :size="15" />
              <span>Change phone</span>
            </button>

            <button
              type="button"
              class="text-button auth-inline-link"
              :disabled="isResendingOtp || resendCooldown > 0"
              @click="handleResendOtp"
            >
              <RotateCw :size="14" :class="{ 'animate-spin': isResendingOtp }" />
              <span v-if="isResendingOtp">Sending...</span>
              <span v-else-if="resendCooldown > 0">Resend in {{ resendCooldown }}s</span>
              <span v-else>Resend SMS OTP</span>
            </button>
          </div>
        </form>

        <!-- STEP 3: VERIFIED ARREARS & M-PESA STK PUSH -->
        <div v-else-if="step === 'pay' && account">
          <p class="eyebrow">STEP 3 OF 3 · VERIFIED RESIDENT</p>
          <h1>{{ account.tenantName }}</h1>
          <p class="subtle" style="display: flex; align-items: center; gap: 6px;">
            <Building2 :size="14" />
            <span>Unit {{ account.unitNumber || 'Suite' }}</span>
            <span v-if="account.leaseNumber">· <span class="mono">{{ account.leaseNumber }}</span></span>
          </p>

          <div style="padding: 16px; border-radius: 10px; border: 1px solid var(--border-color); background: var(--surface-subtle); margin-bottom: 16px;">
            <div style="display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 10px;">
              <span style="font-size: 0.8rem; font-weight: 600; color: var(--text-muted);">
                {{ account.balance > 0 ? 'Current Arrears / Balance Due' : 'Account Standing' }}
              </span>
              <span
                v-if="account.balance > 0"
                style="font-size: 0.72rem; font-weight: 700; padding: 2px 8px; border-radius: 999px; background: #ffedd5; color: #c2410c;"
              >
                Due Now
              </span>
              <span
                v-else
                style="font-size: 0.72rem; font-weight: 700; padding: 2px 8px; border-radius: 999px; background: #dcfce7; color: #15803d;"
              >
                Settled
              </span>
            </div>

            <div style="font-size: 1.9rem; font-weight: 800; color: var(--text-main); letter-spacing: -0.5px;">
              {{ account.balance > 0 ? formatKES(account.balance) : (account.accountCredit > 0 ? `${formatKES(account.accountCredit)} Credit` : 'KES 0') }}
            </div>

            <div style="display: flex; justify-content: space-between; margin-top: 10px; padding-top: 10px; border-top: 1px solid var(--border-color); font-size: 0.78rem; color: var(--text-muted);">
              <span>Monthly Rent: <strong style="color: var(--text-main);">{{ formatKES(account.monthlyRent) }}</strong></span>
              <span v-if="account.nextPaymentDueDate">Next Due: <strong style="color: var(--text-main);">{{ formatHumanDate(account.nextPaymentDueDate) }}</strong></span>
            </div>
          </div>

          <!-- Official Paybill & Anti-Fraud Notice -->
          <div style="padding: 12px 14px; border-radius: 10px; border: 1px solid #e2e8f0; background: #ffffff; margin-bottom: 16px; font-size: 0.78rem;">
            <div style="display: flex; justify-content: space-between; gap: 10px; margin-bottom: 6px;">
              <span>Paybill: <strong class="mono" style="color: #111b35;">522533</strong></span>
              <span>Account No: <strong class="mono" style="color: #111b35;">8107578</strong></span>
            </div>
            <p style="margin: 0 0 6px; color: #334155;">
              You will receive a message confirming payment to <strong>LAPIS APARTMENTS LIMITED</strong>.
            </p>
            <p style="margin: 0; color: #b45309; font-weight: 600; line-height: 1.35;">
              NB: To avoid fraud and losing money, DO NOT pay rent to any other account or to any personal numbers.
            </p>
          </div>

          <div v-if="error" class="auth-alert error">
            <AlertCircle :size="16" class="auth-alert-icon" />
            <span>{{ error }}</span>
          </div>

          <div v-if="isAwaitingPin" style="padding: 18px; border-radius: 10px; background: #eff6ff; border: 1px solid #bfdbfe; text-align: center;">
            <RefreshCw :size="26" class="animate-spin" style="color: var(--accent-primary); margin-bottom: 10px;" />
            <h3 style="font-size: 1rem; margin-bottom: 6px; color: var(--text-main);">Check your phone for M-Pesa PIN prompt</h3>
            <p style="font-size: 0.84rem; color: var(--text-muted); margin-bottom: 14px;">{{ stkStatusText }}</p>

            <div style="display: flex; gap: 8px; justify-content: center;">
              <button
                type="button"
                class="primary-button"
                :disabled="isCheckingStatus"
                @click="checkPaymentStatus(false)"
              >
                <RefreshCw :size="14" :class="{ 'animate-spin': isCheckingStatus }" />
                <span>{{ isCheckingStatus ? 'Checking...' : 'I Have Entered My PIN' }}</span>
              </button>
              <button
                type="button"
                class="secondary-button"
                @click="isAwaitingPin = false; stopStatusPolling()"
              >
                Cancel
              </button>
            </div>
          </div>

          <form v-else @submit.prevent="handleStkPush">
            <label>
              Amount to Pay (KES)
              <input
                v-model.number="payAmount"
                type="number"
                min="1"
                step="1"
                required
                placeholder="Enter amount in KES"
              />
            </label>

            <label>
              M-Pesa Phone Number (STK Push Prompt)
              <PhoneInput v-model="mpesaPhone" required placeholder="712345678" />
            </label>

            <button type="submit" class="primary-button submit" :disabled="isInitiatingStk">
              <CreditCard :size="16" />
              <span>{{ isInitiatingStk ? 'Sending M-Pesa Prompt...' : `Pay ${formatKES(payAmount || 0)} via M-Pesa` }}</span>
            </button>
          </form>
        </div>

        <!-- STEP 4: PAYMENT CONFIRMED RECEIPT -->
        <div v-else-if="step === 'receipt' && receiptInfo && account" style="text-align: center; padding: 10px 0;">
          <div style="width: 56px; height: 56px; border-radius: 999px; background: var(--accent-success-bg); color: var(--accent-success); display: inline-flex; align-items: center; justify-content: center; margin-bottom: 14px;">
            <CheckCircle2 :size="30" />
          </div>

          <p class="eyebrow" style="color: var(--accent-success);">PAYMENT CONFIRMED</p>
          <h1 style="margin-bottom: 8px;">{{ formatKES(receiptInfo.amount) }} Received</h1>
          <p class="subtle">An SMS confirmation receipt has been sent to your phone and your ledger has been updated automatically.</p>

          <div style="text-align: left; padding: 14px 16px; border-radius: 10px; border: 1px solid var(--border-color); background: var(--surface-subtle); display: grid; gap: 8px; font-size: 0.84rem; margin-bottom: 18px;">
            <div style="display: flex; justify-content: space-between;">
              <span style="color: var(--text-muted);">Resident</span>
              <strong>{{ account.tenantName }}</strong>
            </div>
            <div style="display: flex; justify-content: space-between;">
              <span style="color: var(--text-muted);">Unit</span>
              <strong>Unit {{ account.unitNumber }}</strong>
            </div>
            <div style="display: flex; justify-content: space-between;">
              <span style="color: var(--text-muted);">M-Pesa Receipt</span>
              <strong class="mono">{{ receiptInfo.receiptNumber }}</strong>
            </div>
            <div style="display: flex; justify-content: space-between; padding-top: 8px; border-top: 1px solid var(--border-color);">
              <span style="color: var(--text-muted);">Updated Balance</span>
              <strong style="color: var(--accent-success);">
                {{ receiptInfo.remainingBalance > 0 ? `${formatKES(receiptInfo.remainingBalance)} Remaining` : (receiptInfo.accountCredit > 0 ? `${formatKES(receiptInfo.accountCredit)} Credit` : 'Fully Settled') }}
              </strong>
            </div>
          </div>

          <router-link to="/login" class="primary-button submit" style="text-decoration: none; justify-content: center;">
            Sign in to Resident Portal
          </router-link>
        </div>
      </div>
    </section>
  </main>
</template>
