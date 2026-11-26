<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { CheckCircle2, Lock, AlertCircle, Eye, EyeOff, ArrowLeft } from 'lucide-vue-next'

const router = useRouter()
const route = useRoute()

const email = ref('')
const resetToken = ref('')
const code = ref('')
const password = ref('')
const confirmPassword = ref('')
const showPassword = ref(false)
const showConfirmPassword = ref(false)
const error = ref('')
const successMessage = ref('')
const isSubmitting = ref(false)

onMounted(() => {
  try {
    const raw = sessionStorage.getItem('lapis_reset_session')
    if (raw) {
      const parsed = JSON.parse(raw)
      email.value = parsed.email || ''
      resetToken.value = parsed.resetToken || ''
      code.value = parsed.code || ''
    }
  } catch {}

  if (!email.value && route.query.email) {
    email.value = String(route.query.email)
  }
  if (!code.value && route.query.code) {
    code.value = String(route.query.code)
  }
})

const hasValidSession = computed(() => Boolean(resetToken.value || (email.value && code.value)))
const hasMinLength = computed(() => password.value.length >= 6)
const hasLetterAndNumber = computed(() => /[A-Za-z]/.test(password.value) && /\d/.test(password.value))
const passwordsMatch = computed(() => password.value.length > 0 && password.value === confirmPassword.value)

const passwordStrength = computed(() => {
  let score = 0
  if (password.value.length >= 6) score++
  if (password.value.length >= 10) score++
  if (/[A-Z]/.test(password.value) && /[a-z]/.test(password.value)) score++
  if (/\d/.test(password.value)) score++
  if (/[^A-Za-z0-9]/.test(password.value)) score++
  if (score <= 1) return { label: 'Weak', level: 1 }
  if (score <= 3) return { label: 'Good', level: 2 }
  return { label: 'Strong', level: 3 }
})

async function handleReset() {
  error.value = ''
  successMessage.value = ''

  if (!hasValidSession.value) {
    error.value = 'Your verification session is missing or expired. Please request a new SMS OTP.'
    return
  }

  if (!hasMinLength.value) {
    error.value = 'Password must be at least 6 characters long.'
    return
  }

  if (!passwordsMatch.value) {
    error.value = 'Passwords do not match.'
    return
  }

  isSubmitting.value = true
  try {
    const res = await fetch('/api/auth/reset-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: email.value.trim().toLowerCase(),
        resetToken: resetToken.value || undefined,
        code: code.value || undefined,
        password: password.value,
        confirmPassword: confirmPassword.value
      })
    })
    const data = await res.json()
    if (!res.ok) {
      error.value = data.error || 'Failed to reset password. Please try again.'
      return
    }

    sessionStorage.removeItem('lapis_reset_session')
    sessionStorage.removeItem('lapis_recovery_challenge')
    successMessage.value = 'Password updated successfully! Redirecting you to sign in...'
    setTimeout(() => {
      router.push('/login')
    }, 1600)
  } catch (err: any) {
    error.value = err.message || 'Unable to connect to security server.'
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
        <p class="eyebrow">CREDENTIAL UPDATE</p>
        <h1>Set a new password.</h1>
        <p>Your SMS verification succeeded. Choose a strong new password to secure your Lapis Suites account.</p>
      </div>

      <p class="quote">
        “Your credentials grant access to financial ledgers, tenancy agreements, and resident records.”
        <small>— Lapis Suites Account Security</small>
      </p>
    </aside>

    <section class="auth-main">
      <form class="login-card" @submit.prevent="handleReset">
        <div class="mobile-brand">
          <span class="brand-mark">L</span>
          LAPIS SUITES
        </div>

        <div class="auth-steps" aria-label="Recovery steps">
          <div class="auth-step done"><span>✓</span> Account</div>
          <div class="auth-step-line done"></div>
          <div class="auth-step done"><span>✓</span> SMS OTP</div>
          <div class="auth-step-line done"></div>
          <div class="auth-step active"><span>3</span> New Password</div>
        </div>

        <p class="eyebrow">STEP 3 OF 3 · UPDATE SECURITY</p>
        <h1>Reset password</h1>
        <p class="subtle">
          Create a new password
          <template v-if="email"> for <strong>{{ email }}</strong></template>.
        </p>

        <div v-if="!hasValidSession && !successMessage" class="auth-alert error">
          <AlertCircle :size="16" class="auth-alert-icon" />
          <span>No verified OTP session found. Please start from Forgot Password first.</span>
        </div>

        <div v-if="error" class="auth-alert error">
          <AlertCircle :size="16" class="auth-alert-icon" />
          <span>{{ error }}</span>
        </div>

        <div v-if="successMessage" class="auth-alert success">
          <CheckCircle2 :size="16" class="auth-alert-icon" />
          <span>{{ successMessage }}</span>
        </div>

        <label>
          New password
          <div class="password-field">
            <input
              v-model="password"
              :type="showPassword ? 'text' : 'password'"
              required
              minlength="6"
              autocomplete="new-password"
              placeholder="At least 6 characters"
              :disabled="!hasValidSession || !!successMessage"
            />
            <button
              type="button"
              class="password-toggle"
              :aria-label="showPassword ? 'Hide password' : 'Show password'"
              @click="showPassword = !showPassword"
            >
              <EyeOff v-if="showPassword" :size="16" />
              <Eye v-else :size="16" />
            </button>
          </div>
        </label>

        <div v-if="password.length > 0" class="strength-meter">
          <div class="strength-bars">
            <span :class="['strength-seg', { active: passwordStrength.level >= 1, [`lvl-${passwordStrength.level}`]: true }]"></span>
            <span :class="['strength-seg', { active: passwordStrength.level >= 2, [`lvl-${passwordStrength.level}`]: true }]"></span>
            <span :class="['strength-seg', { active: passwordStrength.level >= 3, [`lvl-${passwordStrength.level}`]: true }]"></span>
          </div>
          <span class="strength-label">{{ passwordStrength.label }}</span>
        </div>

        <label>
          Confirm new password
          <div class="password-field">
            <input
              v-model="confirmPassword"
              :type="showConfirmPassword ? 'text' : 'password'"
              required
              minlength="6"
              autocomplete="new-password"
              placeholder="Re-enter new password"
              :disabled="!hasValidSession || !!successMessage"
            />
            <button
              type="button"
              class="password-toggle"
              :aria-label="showConfirmPassword ? 'Hide password' : 'Show password'"
              @click="showConfirmPassword = !showConfirmPassword"
            >
              <EyeOff v-if="showConfirmPassword" :size="16" />
              <Eye v-else :size="16" />
            </button>
          </div>
        </label>

        <ul class="password-checklist">
          <li :class="{ met: hasMinLength }">
            <CheckCircle2 :size="13" /> At least 6 characters
          </li>
          <li :class="{ met: hasLetterAndNumber }">
            <CheckCircle2 :size="13" /> Mix of letters and numbers (recommended)
          </li>
          <li :class="{ met: passwordsMatch }">
            <CheckCircle2 :size="13" /> Both password fields match
          </li>
        </ul>

        <button
          type="submit"
          class="primary-button submit"
          :disabled="isSubmitting || !!successMessage || !hasValidSession || !hasMinLength || !passwordsMatch"
        >
          <Lock :size="15" />
          <span>{{ isSubmitting ? 'Updating password...' : 'Save New Password' }}</span>
        </button>

        <div class="auth-footer-nav center">
          <router-link :to="hasValidSession ? '/login' : '/forgot-password'" class="text-button auth-inline-link">
            <ArrowLeft :size="15" />
            <span>{{ hasValidSession ? 'Back to sign in' : 'Restart password recovery' }}</span>
          </router-link>
        </div>
      </form>
    </section>
  </main>
</template>
