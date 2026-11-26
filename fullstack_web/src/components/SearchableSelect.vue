<script setup lang="ts">
import { ref, computed, watch, nextTick, onMounted, onUnmounted } from 'vue'
import { Search, ChevronDown, Check, X } from 'lucide-vue-next'

export interface SelectOption {
  value: string
  label: string
  sublabel?: string
  disabled?: boolean
}

const props = withDefaults(
  defineProps<{
    modelValue: string | null | undefined
    options: SelectOption[]
    placeholder?: string
    searchPlaceholder?: string
    disabled?: boolean
    clearable?: boolean
  }>(),
  {
    placeholder: 'Select an option...',
    searchPlaceholder: 'Type to filter...',
    disabled: false,
    clearable: false
  }
)

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void
  (e: 'change', value: string): void
}>()

const isOpen = ref(false)
const searchQuery = ref('')
const searchInputRef = ref<HTMLInputElement | null>(null)
const containerRef = ref<HTMLDivElement | null>(null)

const selectedOption = computed(() => {
  return props.options.find(opt => opt.value === props.modelValue) || null
})

const filteredOptions = computed(() => {
  const query = searchQuery.value.trim().toLowerCase()
  if (!query) return props.options
  return props.options.filter(opt =>
    opt.label.toLowerCase().includes(query) ||
    (opt.sublabel && opt.sublabel.toLowerCase().includes(query))
  )
})

function toggleDropdown() {
  if (props.disabled) return
  isOpen.value = !isOpen.value
  if (isOpen.value) {
    searchQuery.value = ''
    nextTick(() => {
      searchInputRef.value?.focus()
    })
  }
}

function selectOption(opt: SelectOption) {
  if (opt.disabled) return
  emit('update:modelValue', opt.value)
  emit('change', opt.value)
  isOpen.value = false
  searchQuery.value = ''
}

function clearSelection(e: MouseEvent) {
  e.stopPropagation()
  emit('update:modelValue', '')
  emit('change', '')
  searchQuery.value = ''
}

function handleClickOutside(e: MouseEvent) {
  if (containerRef.value && !containerRef.value.contains(e.target as Node)) {
    isOpen.value = false
  }
}

function handleKeyDown(e: KeyboardEvent) {
  if (e.key === 'Escape' && isOpen.value) {
    isOpen.value = false
  }
}

onMounted(() => {
  document.addEventListener('click', handleClickOutside)
  document.addEventListener('keydown', handleKeyDown)
})

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside)
  document.removeEventListener('keydown', handleKeyDown)
})
</script>

<template>
  <div ref="containerRef" :class="['searchable-select-container', { open: isOpen, disabled: props.disabled }]">
    <!-- Trigger Button -->
    <button
      type="button"
      class="select-trigger"
      :disabled="props.disabled"
      @click="toggleDropdown"
      :aria-expanded="isOpen"
    >
      <div class="selected-content">
        <template v-if="selectedOption">
          <span class="selected-label">{{ selectedOption.label }}</span>
          <span v-if="selectedOption.sublabel" class="selected-sublabel">· {{ selectedOption.sublabel }}</span>
        </template>
        <span v-else class="placeholder-text">{{ props.placeholder }}</span>
      </div>

      <div class="trigger-actions">
        <button
          v-if="props.clearable && selectedOption && !props.disabled"
          type="button"
          class="clear-btn"
          title="Clear"
          @click="clearSelection"
        >
          <X :size="13" />
        </button>
        <ChevronDown :size="15" class="chevron-icon" />
      </div>
    </button>

    <!-- Dropdown Menu -->
    <div v-if="isOpen" class="select-dropdown">
      <div class="search-input-box" @click.stop>
        <Search :size="14" class="search-icon" />
        <input
          ref="searchInputRef"
          v-model="searchQuery"
          type="text"
          :placeholder="props.searchPlaceholder"
          class="search-field"
        />
        <button
          v-if="searchQuery"
          type="button"
          class="clear-search-btn"
          @click="searchQuery = ''"
        >
          <X :size="12" />
        </button>
      </div>

      <ul class="options-list" role="listbox">
        <li
          v-for="opt in filteredOptions"
          :key="opt.value"
          :class="[
            'option-item',
            {
              selected: opt.value === props.modelValue,
              disabled: opt.disabled
            }
          ]"
          role="option"
          :aria-selected="opt.value === props.modelValue"
          @click="selectOption(opt)"
        >
          <div class="option-info">
            <span class="option-label">{{ opt.label }}</span>
            <small v-if="opt.sublabel" class="option-sublabel">{{ opt.sublabel }}</small>
          </div>
          <Check v-if="opt.value === props.modelValue" :size="14" class="check-icon" />
        </li>

        <li v-if="filteredOptions.length === 0" class="no-options">
          No matches found for "{{ searchQuery }}"
        </li>
      </ul>
    </div>
  </div>
</template>

<style scoped>
.searchable-select-container {
  position: relative;
  width: 100%;
  font-family: inherit;
}

.select-trigger {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  min-height: 38px;
  padding: 8px 12px;
  background: #ffffff;
  border: 1px solid #d0d5dd;
  border-radius: 6px;
  cursor: pointer;
  font: inherit;
  font-size: 0.88rem;
  color: #101828;
  text-align: left;
  transition: all 0.15s ease;
  box-sizing: border-box;
}

.searchable-select-container.open .select-trigger {
  border-color: #2563eb;
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
}

.select-trigger:disabled {
  background: #f8fafc;
  color: #94a3b8;
  cursor: not-allowed;
  border-color: #e2e8f0;
}

.selected-content {
  display: flex;
  align-items: center;
  gap: 6px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex: 1;
}

.selected-label {
  font-weight: 500;
  color: #0f172a;
}

.selected-sublabel {
  font-size: 0.8rem;
  color: #64748b;
}

.placeholder-text {
  color: #94a3b8;
}

.trigger-actions {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-left: 8px;
  flex: none;
}

.chevron-icon {
  color: #64748b;
  transition: transform 0.15s ease;
}

.searchable-select-container.open .chevron-icon {
  transform: rotate(180deg);
}

.clear-btn {
  border: 0;
  background: transparent;
  color: #94a3b8;
  cursor: pointer;
  display: grid;
  place-items: center;
  padding: 2px;
  border-radius: 4px;
}

.clear-btn:hover {
  background: #f1f5f9;
  color: #475467;
}

/* Dropdown */
.select-dropdown {
  position: absolute;
  top: calc(100% + 4px);
  left: 0;
  right: 0;
  z-index: 60;
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  box-shadow: 0 10px 25px -5px rgba(15, 23, 42, 0.12), 0 8px 10px -6px rgba(15, 23, 42, 0.06);
  overflow: hidden;
  max-height: 280px;
  display: flex;
  flex-direction: column;
}

.search-input-box {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-bottom: 1px solid #f1f5f9;
  background: #f8fafc;
}

.search-icon {
  color: #94a3b8;
  flex: none;
}

.search-field {
  width: 100%;
  border: 0;
  background: transparent;
  font: inherit;
  font-size: 0.84rem;
  color: #0f172a;
  outline: none;
}

.clear-search-btn {
  border: 0;
  background: transparent;
  color: #94a3b8;
  cursor: pointer;
  padding: 2px;
}

.options-list {
  list-style: none;
  margin: 0;
  padding: 4px;
  overflow-y: auto;
  max-height: 220px;
}

.option-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 10px;
  border-radius: 5px;
  cursor: pointer;
  transition: background 0.12s ease;
}

.option-item:hover:not(.disabled) {
  background: #f1f5f9;
}

.option-item.selected {
  background: #eff6ff;
  color: #1d4ed8;
}

.option-item.disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.option-info {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.option-label {
  font-size: 0.86rem;
  font-weight: 500;
  color: #1e293b;
}

.option-item.selected .option-label {
  color: #1d4ed8;
  font-weight: 600;
}

.option-sublabel {
  font-size: 0.76rem;
  color: #64748b;
}

.check-icon {
  color: #2563eb;
  flex: none;
}

.no-options {
  padding: 16px;
  text-align: center;
  font-size: 0.82rem;
  color: #94a3b8;
}
</style>
