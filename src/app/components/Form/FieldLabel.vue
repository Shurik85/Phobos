<template>
  <div class="flex items-center">
    <label v-if="forId" :for="forId" class="text-sm">{{ label }}</label>
    <span v-else class="text-sm">{{ label }}</span>
    <BaseTooltip v-if="hint" :text="hint">
      <IconsInfo class="size-4" />
    </BaseTooltip>
  </div>
</template>

<script lang="ts" setup>
defineProps<{ label: string; hint?: string; forId?: string }>();
</script>
