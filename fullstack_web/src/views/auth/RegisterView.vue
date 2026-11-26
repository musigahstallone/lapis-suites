<script setup lang="ts">
import { ref, computed, nextTick } from 'vue'
import { useRouter } from 'vue-router'
import { ArrowLeft, UserPlus, AlertCircle, Eye, EyeOff, CheckCircle2, ShieldCheck, RotateCw } from 'lucide-vue-next'
import { requestResidentRegisterOtp, verifyResidentRegisterOtp } from '../../data'
import PhoneInput from '../../components/PhoneInput.vue'

const router = useRouter()

const step = ref<'details' | 'otp'>('details')
const name = ref('')
const email = ref('')
const phone = ref('')
const password = ref('')
const confirmPassword = ref('')
const showPassword = ref(false)
const showConfirmPassword = ref(false)

// OTP step
const challengeToken = ref('')
const mode = ref<'new' | 'claim'>('new')
const digits = ref<string[]>(['', '', '', '', '', ''])
const inputRefs = ref<(HTMLInputElement | null)[]>([])

const error = ref('')
const info = ref('')
const isSubmitting = ref(false)

const otpCode = computed(() => digits.value.join(''))
const isCodeComplete = computed(() => otpCode.value.length === 6 && /^\d{6}$/.test(otpCode.value))
const passwordsMatch = computed(() => password.value.length > 0 && password.value === confirmPassword.value)

async function handleRequestOtp() {
  error.value = ''
  info.value = ''

  if (!email.value.trim()) {
    error.value = 'Please enter your email address.'
    return
  }
  if (!phone.value || phone.value.replace(/\D/g, '').length !== 12) {
    error.value = 'Please enter a valid 9-digit mobile phone number starting with 7 or 1.'
    return
  }
  if (password.value.length < 6) {
    error.value = 'Password must be at least 6 characters long.'
    return
  }
  if (password.value !== confirmPassword.value) {
    error.value = 'Passwords do not match. Please verify and try again.'
    return
  }

  isSubmitting.value = true
  try {
    const res = await requestResidentRegisterOtp({
      name: name.value.trim(),
      email: email.value.trim().toLowerCase(),
      phone: phone.value,
      password: password.value
    })
    if (!res.ok) {
      error.value = res.error || 'Could not send verification SMS.'
      return
    }
    challengeToken.value = res.challengeToken || ''
    mode.value = res.mode === 'claim' ? 'claim' : 'new'
    info.value = res.message || 'A 6-digit SMS OTP has been sent to your phone.'
    digits.value = ['', '', '', '', '', '']
    step.value = 'otp'
    nextTick(() => inputRefs.value[0]?.focus())
  } catch (err: any) {
    error.value = err.message || 'Connection interrupted. Please try again.'
  } finally {
    isSubmitting.value = false
  }
}

function handleDigitInput(idx: number, event: Event) {
  const input = event.target as HTMLInputElement
  const raw = input.value.replace(/\D/g, '')
  if (raw.length > 1) {
    const chars = raw.slice(0, 6).split('')
    digits.value = ['', '', '', '', '', '']
    chars.forEach((ch, i) => { digits.value[i] = ch })
    nextTick(() => inputRefs.value[Math.min(chars.length, 5)]?.focus())
    return
  }
  digits.value[idx] = raw
  if (raw && idx < 5) nextTick(() => inputRefs.value[idx + 1]?.focus())
}

function handleDigitKeydown(idx: number, event: KeyboardEvent) {
  if (event.key === 'Backspace') {
    if (digits.value[idx]) digits.value[idx] = ''
    else if (idx > 0) {
      digits.value[idx - 1] = ''
      nextTick(() => inputRefs.value[idx - 1]?.focus())
    }
  }
}

function handlePaste(event: ClipboardEvent) {
  const pasted = (event.clipboardData?.getData('text') || '').replace(/\D/g, '').slice(0, 6)
  if (!pasted) return
  event.preventDefault()
  digits.value = ['', '', '', '', '', '']
  pasted.split('').forEach((ch, i) => { digits.value[i] = ch })
  nextTick(() => inputRefs.value[Math.min(pasted.length, 5)]?.focus())
}

async function handleVerifyOtp() {
  error.value = ''
  if (!isCodeComplete.value) {
    error.value = 'Please enter all 6 digits of your SMS verification code.'
    return
  }

  isSubmitting.value = true
  try {
    const res = await verifyResidentRegisterOtp(challengeToken.value, otpCode.value)
    if (!res.ok) {
      error.value = res.error || 'Verification code is invalid or expired.'
      digits.value = ['', '', '', '', '', '']
      nextTick(() => inputRefs.value[0]?.focus())
      return
    }
    router.push('/tenant/home')
  } catch (err: any) {
    error.value = err.message || 'Connection interrupted. Please try again.'
  } finally {
    isSubmitting.value = false
  }
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
        <p class="eyebrow">RESIDENT PORTAL SETUP</p>
        <h1>Activate or create your resident account.</h1>
        <p>Whether management already added your unit profile or you are registering fresh, confirm your mobile number via SMS OTP to set a secure password.</p>
      </div>

      <p class="quote">
        “Direct digital rent verification with automatic M-Pesa reconciliation and instant receipts.”
        <small>— Resident Services Desk</small>
      </p>
    </aside>

    <section class="auth-main">
      <div class="login-card">
        <div class="mobile-brand">
          <span class="brand-mark">L</span>
          LAPIS SUITES
        </div>

        <div class="auth-steps">
          <div :class="['auth-step', step === 'details' ? 'active' : 'done']">
            <span>{{ step === 'details' ? '1' : '✓' }}</span> Details &amp; Password
          </div>
          <div :class="['auth-step-line', step === 'otp' ? 'done' : '']"></div>
          <div :class="['auth-step', step === 'otp' ? 'active' : '']">
            <span>2</span> SMS OTP
          </div>
        </div>

        <!-- STEP 1: ACCOUNT DETAILS & PASSWORD -->
        <form v-if="step === 'details'" @submit.prevent="handleRequestOtp">
          <p class="eyebrow">STEP 1 OF 2 · RESIDENT ONBOARDING</p>
          <h1>Create resident account</h1>
          <p class="subtle">Enter your details and choose a secure password. We will send an SMS OTP to confirm.</p>

          <div v-if="error" class="auth-alert error">
            <AlertCircle :size="16" class="auth-alert-icon" />
            <span>{{ error }}</span>
          </div>

          <label>
            Full Name
            <input
              v-model="name"
              type="text"
              autocomplete="name"
              placeholder="e.g. John Kamau"
            />
          </label>

          <label>
            Email address
            <input
              v-model="email"
              type="email"
              required
              autocomplete="email"
              placeholder="john.kamau@example.com"
            />
          </label>

          <label>
            Mobile Phone Number
            <PhoneInput v-model="phone" required placeholder="712345678" />
          </label>

          <label>
            Create Secure Password
            <div class="password-field">
              <input
                v-model="password"
                :type="showPassword ? 'text' : 'password'"
                required
                minlength="6"
                autocomplete="new-password"
                placeholder="At least 6 characters"
              />
              <button type="button" class="password-toggle" @click="showPassword = !showPassword">
                <EyeOff v-if="showPassword" :size="16" />
                <Eye v-else :size="16" />
              </button>
            </div>
          </label>

          <label>
            Confirm Password
            <div class="password-field">
              <input
                v-model="confirmPassword"
                :type="showConfirmPassword ? 'text' : 'password'"
                required
                minlength="6"
                autocomplete="new-password"
                placeholder="Re-enter password"
              />
              <button type="button" class="password-toggle" @click="showConfirmPassword = !showConfirmPassword">
                <EyeOff v-if="showConfirmPassword" :size="16" />
                <Eye v-else :size="16" />
              </button>
            </div>
          </label>

          <div v-if="passwordsMatch" class="auth-match-hint ok">
            <CheckCircle2 :size="14" />
            <span>Passwords match</span>
          </div>

          <button type="submit" class="primary-button submit" :disabled="isSubmitting">
            <UserPlus :size="16" />
            <span>{{ isSubmitting ? 'Sending SMS OTP...' : 'Continue & Send SMS OTP' }}</span>
          </button>

          <div class="auth-footer-nav center">
            <router-link to="/login" class="text-button auth-inline-link">
              <ArrowLeft :size="15" />
              <span>Already registered? Sign in</span>
            </router-link>
          </div>
        </form>

        <!-- STEP 2: VERIFY 6-DIGIT SMS OTP -->
        <form v-else @submit.prevent="handleVerifyOtp">
          <p class="eyebrow">STEP 2 OF 2 · SMS CONFIRMATION</p>
          <h1>{{ mode === 'claim' ? 'Activate your profile' : 'Confirm your phone' }}</h1>
          <p class="subtle">Enter the 6-digit verification code sent via SMS to complete setup.</p>

          <div v-if="info" class="auth-alert success">
            <CheckCircle2 :size="16" class="auth-alert-icon" />
            <span>{{ info }}</span>
          </div>

          <div v-if="error" class="auth-alert error">
            <AlertCircle :size="16" class="auth-alert-icon" />
            <span>{{ error }}</span>
          </div>

          <div class="otp-grid" style="margin: 16px 0 8px;" @paste="handlePaste">
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
              @input="handleDigitInput(idx, $event)"
              @keydown="handleDigitKeydown(idx, $event)"
            />
          </div>

          <button type="submit" class="primary-button submit" :disabled="isSubmitting || !isCodeComplete">
            <ShieldCheck :size="16" />
            <span>{{ isSubmitting ? 'Verifying...' : 'Verify OTP & Open Portal' }}</span>
          </button>

          <div class="auth-footer-nav between">
            <button type="button" class="text-button auth-inline-link" @click="step = 'details'; error = ''">
              <ArrowLeft :size="15" /> Back
            </button>
            <button type="button" class="text-button auth-inline-link" :disabled="isSubmitting" @click="handleRequestOtp">
              <RotateCw :size="14" :class="{ 'animate-spin': isSubmitting }" /> Resend OTP
            </button>
          </div>
        </form>
      </div>
    </section>
  </main>
</template>
