<script setup lang="ts">
import { computed } from 'vue'
import { ChevronLeft, ChevronRight } from 'lucide-vue-next'

const props = defineProps<{
  currentPage: number
  pageSize: number
  totalItems: number
}>()

const emit = defineEmits<{
  (e: 'update:currentPage', page: number): void
  (e: 'update:pageSize', size: number): void
}>()

const totalPages = computed(() => {
  return Math.ceil(props.totalItems / props.pageSize) || 1
})

const startItem = computed(() => {
  if (props.totalItems === 0) return 0
  return (props.currentPage - 1) * props.pageSize + 1
})

const endItem = computed(() => {
  return Math.min(props.currentPage * props.pageSize, props.totalItems)
})

function setPage(page: number) {
  if (page >= 1 && page <= totalPages.value) {
    emit('update:currentPage', page)
  }
}

function onPageSizeChange(e: Event) {
  const target = e.target as HTMLSelectElement
  emit('update:pageSize', Number(target.value))
  emit('update:currentPage', 1)
}
</script>

<template>
  <div class="pagination-container">
    <div class="pagination-info">
      <span>
        Showing <strong>{{ startItem }}</strong> to <strong>{{ endItem }}</strong> of <strong>{{ totalItems }}</strong> entries
      </span>
      <div class="page-size-selector">
        <label>Per page:</label>
        <select :value="pageSize" @change="onPageSizeChange">
          <option :value="5">5</option>
          <option :value="10">10</option>
          <option :value="25">25</option>
        </select>
      </div>
    </div>

    <div v-if="totalPages > 1" class="pagination-nav">
      <button
        type="button"
        class="pagination-btn"
        :disabled="currentPage === 1"
        @click="setPage(currentPage - 1)"
        aria-label="Previous page"
      >
        <ChevronLeft :size="15" />
      </button>

      <button
        v-for="p in totalPages"
        :key="p"
        type="button"
        :class="['pagination-page-btn', { active: currentPage === p }]"
        @click="setPage(p)"
      >
        {{ p }}
      </button>

      <button
        type="button"
        class="pagination-btn"
        :disabled="currentPage === totalPages"
        @click="setPage(currentPage + 1)"
        aria-label="Next page"
      >
        <ChevronRight :size="15" />
      </button>
    </div>
  </div>
</template>

<style scoped>
.pagination-container {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 12px 18px;
  background-color: #fafbfc;
  border-top: 1px solid #e2e8f0;
  font-size: 0.78rem;
  color: #64748b;
  flex-wrap: wrap;
}

.pagination-info {
  display: flex;
  align-items: center;
  gap: 16px;
  flex-wrap: wrap;
}

.pagination-info strong {
  color: #172033;
}

.page-size-selector {
  display: flex;
  align-items: center;
  gap: 6px;
}

.page-size-selector select {
  padding: 2px 6px;
  border-radius: 4px;
  border: 1px solid #cbd5e1;
  background: #ffffff;
  font-size: 0.78rem;
  color: #172033;
  outline: none;
}

.pagination-nav {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-left: auto;
}

.pagination-btn, .pagination-page-btn {
  display: grid;
  place-items: center;
  min-width: 28px;
  height: 28px;
  border: 1px solid #e2e8f0;
  border-radius: 5px;
  background: #ffffff;
  color: #475467;
  font-size: 0.78rem;
  font-weight: 500;
  cursor: pointer;
  padding: 0 6px;
  transition: all 0.12s ease;
}

.pagination-btn:hover:not(:disabled), .pagination-page-btn:hover:not(.active) {
  background: #f1f5f9;
  color: #172033;
}

.pagination-page-btn.active {
  background: #2563eb;
  border-color: #2563eb;
  color: #ffffff;
  font-weight: 700;
}

.pagination-btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

@media (max-width: 600px) {
  .pagination-container {
    flex-direction: column;
    align-items: stretch;
    gap: 10px;
  }
  .pagination-nav {
    justify-content: center;
    margin-left: 0;
  }
}
</style>
