<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    modelValue: string
    placeholder?: string
    required?: boolean
    disabled?: boolean
    id?: string
  }>(),
  {
    placeholder: '712345678',
    required: false,
    disabled: false,
    id: undefined
  }
)

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void
}>()

function extractLocalNine(raw: string): string {
  let digits = String(raw || '').replace(/\D/g, '')
  if (digits.startsWith('254')) {
    digits = digits.slice(3)
  } else if (digits.startsWith('0')) {
    digits = digits.slice(1)
  }
  return digits.slice(0, 9)
}

const localDigits = computed(() => extractLocalNine(props.modelValue))

const isValidLength = computed(() => {
  if (!localDigits.value) return true
  return /^[17]\d{8}$/.test(localDigits.value)
})

function handleInput(event: Event) {
  const input = event.target as HTMLInputElement
  const cleaned = extractLocalNine(input.value)
  if (input.value !== cleaned) {
    input.value = cleaned
  }
  emit('update:modelValue', cleaned ? `254${cleaned}` : '')
}

function handlePaste(event: ClipboardEvent) {
  const pasted = event.clipboardData?.getData('text') || ''
  if (!pasted) return
  event.preventDefault()
  const cleaned = extractLocalNine(pasted)
  emit('update:modelValue', cleaned ? `254${cleaned}` : '')
}
</script>

<template>
  <div class="ke-phone-wrap" :class="{ disabled, invalid: localDigits.length === 9 && !isValidLength }">
    <span class="ke-phone-prefix" aria-hidden="true">+254</span>
    <input
      :id="id"
      :value="localDigits"
      type="tel"
      inputmode="numeric"
      maxlength="9"
      pattern="[17][0-9]{8}"
      title="Enter 9 digits starting with 7 or 1 (e.g. 712345678)"
      :placeholder="placeholder"
      :required="required"
      :disabled="disabled"
      class="ke-phone-input"
      @input="handleInput"
      @paste="handlePaste"
    />
  </div>
</template>

<style scoped>
.ke-phone-wrap {
  display: flex;
  align-items: stretch;
  width: 100%;
  margin-top: 6px;
  border: 1px solid var(--border-color, #cbd5e1);
  border-radius: 6px;
  background: #ffffff;
  overflow: hidden;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}

.ke-phone-wrap:focus-within {
  border-color: var(--accent-primary, #2563eb);
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
}

.ke-phone-wrap.disabled {
  background: #f8fafc;
  opacity: 0.75;
}

.ke-phone-wrap.invalid {
  border-color: #dc2626;
}

.ke-phone-prefix {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0 11px;
  background: #f1f5f9;
  border-right: 1px solid var(--border-color, #e2e8f0);
  color: #334155;
  font-size: 0.86rem;
  font-weight: 700;
  user-select: none;
  flex-shrink: 0;
}

.ke-phone-input {
  flex: 1;
  width: 100%;
  min-width: 0;
  border: none !important;
  outline: none !important;
  box-shadow: none !important;
  margin: 0 !important;
  padding: 9px 12px !important;
  font: inherit;
  font-size: 0.88rem;
  background: transparent;
  color: var(--text-main, #172033);
}
</style>
