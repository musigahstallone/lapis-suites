<script setup lang="ts">
import { watch, onMounted, onUnmounted } from 'vue'
import { X } from 'lucide-vue-next'

const props = defineProps<{
  open: boolean
  title: string
  subtitle?: string
  width?: string
}>()

const emit = defineEmits<{
  (e: 'close'): void
}>()

function handleKeyDown(e: KeyboardEvent) {
  if (e.key === 'Escape' && props.open) {
    emit('close')
  }
}

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      document.body.style.overflow = 'hidden'
    } else {
      document.body.style.overflow = ''
    }
  }
)

onMounted(() => {
  window.addEventListener('keydown', handleKeyDown)
})

onUnmounted(() => {
  window.removeEventListener('keydown', handleKeyDown)
  document.body.style.overflow = ''
})
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="sidesheet-backdrop"
      @click="emit('close')"
      aria-modal="true"
      role="dialog"
    >
      <div
        class="sidesheet-panel"
        :style="{ maxWidth: width || '480px' }"
        @click.stop
      >
        <!-- Header -->
        <div class="sidesheet-header">
          <div class="sidesheet-title-block">
            <h2>{{ title }}</h2>
            <p v-if="subtitle">{{ subtitle }}</p>
          </div>
          <button
            type="button"
            class="sidesheet-close-btn"
            @click="emit('close')"
            aria-label="Close"
          >
            <X :size="18" />
          </button>
        </div>

        <!-- Scrollable Content -->
        <div class="sidesheet-body">
          <slot />
        </div>

        <!-- Optional Footer Actions -->
        <div v-if="$slots.footer" class="sidesheet-footer">
          <slot name="footer" />
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.sidesheet-backdrop {
  position: fixed;
  inset: 0;
  z-index: 100;
  background-color: rgba(17, 27, 53, 0.45);
  backdrop-filter: blur(2px);
  display: flex;
  justify-content: flex-end;
  animation: fadeIn 0.18s ease-out;
}

.sidesheet-panel {
  width: 100%;
  height: 100vh;
  background-color: #ffffff;
  box-shadow: -8px 0 28px rgba(17, 27, 53, 0.12);
  display: flex;
  flex-direction: column;
  animation: slideRight 0.22s cubic-bezier(0.16, 1, 0.3, 1);
  border-left: 1px solid #e2e8f0;
}

.sidesheet-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  padding: 18px 22px;
  border-bottom: 1px solid #eef2f6;
  background-color: #fafbfc;
  flex: none;
}

.sidesheet-title-block h2 {
  font-size: 1.15rem;
  font-weight: 700;
  color: #172033;
  margin: 0;
}

.sidesheet-title-block p {
  font-size: 0.8rem;
  color: #64748b;
  margin: 3px 0 0;
}

.sidesheet-close-btn {
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border-radius: 6px;
  border: 1px solid #e2e8f0;
  background: #ffffff;
  color: #475467;
  cursor: pointer;
  flex: none;
  transition: all 0.12s ease;
}

.sidesheet-close-btn:hover {
  background: #f1f5f9;
  color: #172033;
}

.sidesheet-body {
  flex: 1;
  overflow-y: auto;
  padding: 22px;
}

.sidesheet-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 10px;
  padding: 16px 22px;
  border-top: 1px solid #eef2f6;
  background-color: #fafbfc;
  flex: none;
}

@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}

@keyframes slideRight {
  from { transform: translateX(100%); }
  to { transform: translateX(0); }
}

/* Mobile responsive requirement:
   On mobile screens, expand to fill display except for ~10% margin at top
   that acts as backdrop tap target to dismiss the sheet. */
@media (max-width: 640px) {
  .sidesheet-backdrop {
    align-items: flex-end;
  }
  .sidesheet-panel {
    height: 90vh;
    max-height: 90vh;
    border-radius: 14px 14px 0 0;
    border-left: none;
    border-top: 1px solid #e2e8f0;
    animation: slideUp 0.22s cubic-bezier(0.16, 1, 0.3, 1);
  }
}

@keyframes slideUp {
  from { transform: translateY(100%); }
  to { transform: translateY(0); }
}
</style>
