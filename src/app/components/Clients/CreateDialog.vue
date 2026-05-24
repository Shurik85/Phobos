<template>
  <BaseDialog :trigger-class="triggerClass">
    <template #trigger>
      <slot />
    </template>
    <template #title>
      {{ $t('client.new') }}
    </template>
    <template #description>
      <div class="flex flex-col gap-2">
        <FormTextField id="name" v-model="name" :label="$t('client.name')" />
        <FormDateField
          id="expiresAt"
          v-model="expiresAt"
          :label="$t('client.expireDate')"
        />
        <div class="flex flex-col gap-1">
          <FormLabel for="presetId">{{ $t('client.preset') }}</FormLabel>
          <select
            id="presetId"
            v-model="presetId"
            class="rounded border-2 border-gray-100 px-3 py-2 text-sm dark:border-neutral-700 dark:bg-neutral-800"
          >
            <option :value="null">{{ $t('client.presetUseDefault') }}</option>
            <option
              v-for="p in presets ?? []"
              :key="p.id"
              :value="p.id"
            >
              {{ p.name }}{{ p.isDefault ? ' (default)' : '' }}
            </option>
          </select>
        </div>
      </div>
    </template>
    <template #actions>
      <DialogClose as-child>
        <BaseSecondaryButton>{{ $t('dialog.cancel') }}</BaseSecondaryButton>
      </DialogClose>
      <DialogClose as-child>
        <BasePrimaryButton @click="createClient">
          {{ $t('client.create') }}
        </BasePrimaryButton>
      </DialogClose>
    </template>
  </BaseDialog>
</template>

<script lang="ts" setup>
type PresetSummary = {
  id: number;
  name: string;
  isDefault: boolean;
};

const name = ref<string>('');
const expiresAt = ref<string | null>(null);
const presetId = ref<number | null>(null);
const clientsStore = useClientsStore();

const { t } = useI18n();

defineProps<{ triggerClass?: string }>();

const { data: presets } = await useFetch<PresetSummary[]>(
  '/api/admin/obfuscator-presets',
  { method: 'get', default: () => [] }
);

function createClient() {
  return _createClient({
    name: name.value,
    expiresAt: expiresAt.value,
    presetId: presetId.value,
  });
}

const _createClient = useSubmit(
  '/api/client',
  {
    method: 'post',
  },
  {
    revert: () => clientsStore.refresh(),
    successMsg: t('client.created'),
  }
);
</script>
