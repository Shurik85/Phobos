<template>
  <div class="relative mt-2 h-10 w-10 self-start rounded-full bg-gray-50">
    <BaseAvatar :img="client.avatar" class="h-10 w-10">
      <IconsAvatar class="h-6 w-6 text-gray-300" />
    </BaseAvatar>

    <span
      v-if="active"
      class="pointer-events-none absolute -bottom-1 -right-1 flex h-4 w-4"
    >
      <span
        class="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-500 opacity-60"
      />
      <span
        class="absolute inline-flex h-full w-full animate-ping rounded-full bg-green-500 opacity-60 [animation-delay:0.6s]"
      />
    </span>

    <Transition name="peer-dot">
      <div
        v-if="connected"
        class="absolute bottom-0 right-0 h-2.5 w-2.5 rounded-full bg-green-500 ring-2 ring-white dark:ring-neutral-800"
      />
      <div
        v-else
        class="absolute bottom-0 right-0 h-2.5 w-2.5 rounded-full bg-gray-300 ring-2 ring-white dark:bg-neutral-600 dark:ring-neutral-800"
      />
    </Transition>
  </div>
</template>

<script setup lang="ts">
const props = defineProps<{
  client: LocalClient;
}>();

const connected = computed(() =>
  isPeerConnected({
    latestHandshakeAt: props.client.latestHandshakeAt
      ? new Date(props.client.latestHandshakeAt)
      : null,
  })
);

const active = computed(
  () =>
    connected.value &&
    (props.client.transferRxCurrent ?? 0) +
      (props.client.transferTxCurrent ?? 0) >
      0
);
</script>

<style scoped lang="css">
.peer-dot-enter-active,
.peer-dot-leave-active {
  transition:
    transform 0.3s ease,
    opacity 0.3s ease;
}

.peer-dot-enter-from,
.peer-dot-leave-to {
  transform: scale(0);
  opacity: 0;
}
</style>
