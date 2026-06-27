<template>
  <ClientOnly>
    <component
      :is="ApexChart"
      width="100%"
      height="100%"
      v-bind="$attrs"
      :options="options"
      :series="series"
    />
  </ClientOnly>
</template>

<script setup lang="ts">
import { defineAsyncComponent } from 'vue';
import type { VueApexChartsComponentProps } from 'vue3-apexcharts';

defineProps<{
  options: VueApexChartsComponentProps['options'];
  series: VueApexChartsComponentProps['series'];
}>();

const ApexChart = defineAsyncComponent(() => import('vue3-apexcharts'));
</script>
