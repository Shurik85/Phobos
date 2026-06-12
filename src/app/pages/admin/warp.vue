<template>
  <main v-if="data">
    <FormElement v-if="!data.registered" @submit.prevent="register">
      <FormGroup>
        <FormHeading>{{ $t('admin.warp.title') }}</FormHeading>
        <p class="col-span-2 text-sm text-gray-500 dark:text-neutral-400">
          {{ $t('admin.warp.intro') }}
        </p>
        <FormPrimaryActionField
          type="submit"
          :label="$t('admin.warp.register')"
        />
      </FormGroup>
    </FormElement>

    <FormElement v-else @submit.prevent="() => {}">
      <FormGroup>
        <FormHeading>{{ $t('admin.warp.status') }}</FormHeading>
        <FormInfoField
          id="deviceId"
          :label="$t('admin.warp.deviceId')"
          :data="data.deviceId"
        />
        <FormInfoField
          id="addressV4"
          :label="$t('admin.warp.addressV4')"
          :data="data.addressV4"
        />
        <FormInfoField
          id="addressV6"
          :label="$t('admin.warp.addressV6')"
          :data="data.addressV6"
        />
        <FormInfoField
          id="endpoint"
          :label="$t('admin.warp.endpoint')"
          :data="data.endpoint"
        />
        <FormInfoField
          id="egress"
          :label="$t('admin.warp.egress')"
          :description="$t('admin.warp.egressDesc')"
          :data="
            data.egressMode === 'warp'
              ? $t('admin.warp.egressActive')
              : $t('admin.warp.egressInactive')
          "
        />
      </FormGroup>

      <FormGroup>
        <FormHeading>{{ $t('admin.warp.license') }}</FormHeading>
        <FormTextField
          id="license"
          v-model="license"
          :label="$t('admin.warp.licenseKey')"
          :description="$t('admin.warp.licenseKeyDesc')"
          :placeholder="
            data.hasLicense
              ? $t('admin.warp.licenseSet')
              : $t('admin.warp.licenseUnset')
          "
        />
        <FormSecondaryActionField
          :label="$t('admin.warp.applyLicense')"
          @click="applyLicense"
        />
      </FormGroup>

      <FormGroup>
        <FormHeading>{{ $t('admin.warp.autoRotate') }}</FormHeading>
        <FormNumberField
          id="interval"
          v-model="interval"
          :label="$t('admin.warp.intervalDays')"
          :description="$t('admin.warp.intervalDaysDesc')"
        />
        <FormSecondaryActionField
          :label="$t('form.save')"
          @click="saveInterval"
        />
      </FormGroup>

      <FormGroup>
        <FormHeading>{{ $t('form.actions') }}</FormHeading>
        <FormSecondaryActionField
          :label="$t('admin.warp.changeIp')"
          @click="changeIp"
        />
        <FormSecondaryActionField
          :label="$t('admin.warp.importConfig')"
          @click="importOpen = true"
        />
        <FormSecondaryActionField
          :label="$t('admin.warp.delete')"
          @click="remove"
        />
      </FormGroup>
    </FormElement>

    <WarpImportDialog v-model:open="importOpen" @success="revert" />
  </main>
</template>

<script setup lang="ts">
const { t } = useI18n();

const { data: _data, refresh } = await useFetch(`/api/admin/warp`, {
  method: 'get',
});

const data = toRef(_data.value);

const license = ref('');
const interval = ref(data.value?.updateIntervalDays ?? 0);
const importOpen = ref(false);

async function revert() {
  await refresh();
  data.value = toRef(_data.value).value;
  license.value = '';
  interval.value = data.value?.updateIntervalDays ?? 0;
}

const _register = useSubmit(
  `/api/admin/warp/register`,
  { method: 'post' },
  { revert, successMsg: t('admin.warp.registerSuccess') }
);

const _applyLicense = useSubmit(
  `/api/admin/warp/license`,
  { method: 'post' },
  { revert, successMsg: t('admin.warp.licenseSuccess') }
);

const _saveInterval = useSubmit(
  `/api/admin/warp/interval`,
  { method: 'post' },
  { revert }
);

const _changeIp = useSubmit(
  `/api/admin/warp/change-ip`,
  { method: 'post' },
  { revert, successMsg: t('admin.warp.changeIpSuccess') }
);

const _remove = useSubmit(
  `/api/admin/warp`,
  { method: 'delete' },
  { revert, successMsg: t('admin.warp.deleteSuccess') }
);

function register() {
  return _register(undefined);
}

function applyLicense() {
  return _applyLicense({ license: license.value });
}

function saveInterval() {
  return _saveInterval({ updateIntervalDays: interval.value });
}

function changeIp() {
  return _changeIp(undefined);
}

function remove() {
  return _remove(undefined);
}
</script>
