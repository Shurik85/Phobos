<template>
  <div>
    <p class="text-center text-lg">
      {{ $t('setup.setupConfigDesc') }}
    </p>
    <div class="mt-8 flex flex-col gap-3">
      <div class="flex flex-col">
        <FormHostField
          id="host"
          v-model="host"
          :label="$t('general.host')"
          placeholder="vpn.example.com"
          :description="$t('setup.hostDesc')"
          url="/api/setup/4"
        />
      </div>
      <div class="mt-4 flex justify-center">
        <BasePrimaryButton @click="submit">
          {{ $t('general.continue') }}
        </BasePrimaryButton>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
definePageMeta({
  layout: 'setup',
});

const setupStore = useSetupStore();
setupStore.setStep(4);

const host = ref<null | string>(null);

const _submit = useSubmit(
  '/api/setup/4',
  {
    method: 'post',
  },
  {
    revert: async (success) => {
      if (success) {
        await navigateTo('/setup/5');
      }
    },
    noSuccessToast: true,
  }
);

function submit() {
  return _submit({ host: host.value });
}
</script>
