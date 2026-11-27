<script setup lang="ts">
withDefaults(defineProps<{
  variant?: 'dashboard' | 'cards' | 'list'
  rows?: number
}>(), {
  variant: 'dashboard',
  rows: 4
})
</script>

<template>
  <div class="lapis-skeleton-wrap" aria-busy="true" aria-label="Loading content">
    <template v-if="variant === 'dashboard'">
      <div class="sk-kpi-grid">
        <div v-for="n in 4" :key="n" class="sk-card">
          <div class="sk-line sk-w-45 sk-h-12"></div>
          <div class="sk-line sk-w-65 sk-h-24" style="margin-top: 12px;"></div>
          <div class="sk-line sk-w-55 sk-h-10" style="margin-top: 10px;"></div>
        </div>
      </div>
      <div class="sk-panel" style="margin-top: 20px;">
        <div class="sk-line sk-w-35 sk-h-16" style="margin-bottom: 16px;"></div>
        <div v-for="i in rows" :key="i" class="sk-row">
          <div class="sk-circle"></div>
          <div style="flex: 1; display: flex; flex-direction: column; gap: 7px;">
            <div class="sk-line sk-w-40 sk-h-12"></div>
            <div class="sk-line sk-w-25 sk-h-10"></div>
          </div>
          <div class="sk-line sk-w-18 sk-h-14"></div>
        </div>
      </div>
    </template>

    <template v-else-if="variant === 'cards'">
      <div class="sk-two-col">
        <div v-for="n in 2" :key="n" class="sk-card">
          <div class="sk-line sk-w-35 sk-h-12"></div>
          <div class="sk-line sk-w-60 sk-h-26" style="margin-top: 12px;"></div>
          <div class="sk-line sk-w-80 sk-h-10" style="margin-top: 10px;"></div>
          <div class="sk-line sk-w-100 sk-h-36" style="margin-top: 18px; border-radius: 8px;"></div>
        </div>
      </div>
      <div class="sk-panel" style="margin-top: 20px;">
        <div v-for="i in rows" :key="i" class="sk-row">
          <div class="sk-circle"></div>
          <div style="flex: 1; display: flex; flex-direction: column; gap: 7px;">
            <div class="sk-line sk-w-45 sk-h-12"></div>
            <div class="sk-line sk-w-30 sk-h-10"></div>
          </div>
          <div class="sk-line sk-w-18 sk-h-14"></div>
        </div>
      </div>
    </template>

    <template v-else>
      <div class="sk-panel">
        <div v-for="i in rows" :key="i" class="sk-row">
          <div class="sk-circle"></div>
          <div style="flex: 1; display: flex; flex-direction: column; gap: 7px;">
            <div class="sk-line sk-w-45 sk-h-12"></div>
            <div class="sk-line sk-w-28 sk-h-10"></div>
          </div>
          <div class="sk-line sk-w-18 sk-h-14"></div>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.lapis-skeleton-wrap {
  width: 100%;
}

.sk-kpi-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
  gap: 16px;
}

.sk-two-col {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 18px;
}

.sk-card,
.sk-panel {
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  padding: 18px 20px;
}

.sk-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid #f1f5f9;
}

.sk-row:last-child {
  border-bottom: none;
  padding-bottom: 0;
}

.sk-circle {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  flex-shrink: 0;
  background: linear-gradient(90deg, #f1f5f9 25%, #e2e8f0 50%, #f1f5f9 75%);
  background-size: 200% 100%;
  animation: lapisShimmer 1.3s ease-in-out infinite;
}

.sk-line {
  border-radius: 6px;
  background: linear-gradient(90deg, #f1f5f9 25%, #e2e8f0 50%, #f1f5f9 75%);
  background-size: 200% 100%;
  animation: lapisShimmer 1.3s ease-in-out infinite;
}

.sk-h-10 { height: 10px; }
.sk-h-12 { height: 12px; }
.sk-h-14 { height: 14px; }
.sk-h-16 { height: 16px; }
.sk-h-24 { height: 24px; }
.sk-h-26 { height: 26px; }
.sk-h-36 { height: 36px; }

.sk-w-18 { width: 18%; }
.sk-w-25 { width: 25%; }
.sk-w-28 { width: 28%; }
.sk-w-30 { width: 30%; }
.sk-w-35 { width: 35%; }
.sk-w-40 { width: 40%; }
.sk-w-45 { width: 45%; }
.sk-w-55 { width: 55%; }
.sk-w-60 { width: 60%; }
.sk-w-65 { width: 65%; }
.sk-w-80 { width: 80%; }
.sk-w-100 { width: 100%; }

@keyframes lapisShimmer {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}
</style>
