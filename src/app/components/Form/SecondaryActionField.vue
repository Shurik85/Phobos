<template>
  <input
    :value="label"
    :type="type ?? 'button'"
    :disabled="disabled"
    class="col-span-2 rounded-lg border-2 border-gray-100 py-2 text-gray-500 hover:border-red-800 hover:bg-red-800 hover:text-white focus:border-red-800 focus:outline-0 focus:ring-0 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:border-gray-100 disabled:hover:bg-transparent disabled:hover:text-gray-500 dark:border-neutral-800 dark:bg-neutral-700 dark:text-neutral-200 dark:placeholder:text-neutral-400 dark:disabled:hover:border-neutral-800 dark:disabled:hover:bg-neutral-700 dark:disabled:hover:text-neutral-200"
  />
</template>

<script lang="ts" setup>
import type { InputTypeHTMLAttribute } from 'vue';

defineProps<{
  label: string;
  type?: InputTypeHTMLAttribute;
  disabled?: boolean;
}>();
</script>
