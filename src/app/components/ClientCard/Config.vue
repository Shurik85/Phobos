<template>
  <a
    :href="`/api/client/${client.id}/package.tar.gz`"
    :download="filename"
    class="inline-block rounded bg-gray-100 p-2 align-middle transition hover:bg-red-800 hover:text-white dark:bg-neutral-600 dark:text-neutral-300 dark:hover:bg-red-800 dark:hover:text-white"
    :title="$t('client.downloadPackage')"
  >
    <IconsDownload class="w-5" />
  </a>
</template>

<script setup lang="ts">
const props = defineProps<{
  client: LocalClient;
}>();

const filename = computed(() => {
  const slug =
    props.client.name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 32) || `client-${props.client.id}`;
  return `phobos-${slug}.tar.gz`;
});
</script>
