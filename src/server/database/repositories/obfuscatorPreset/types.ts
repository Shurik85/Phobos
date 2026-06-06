import type { InferSelectModel } from 'drizzle-orm';
import z from 'zod';

import type { obfuscatorPreset } from './schema';

export type ObfuscatorPresetType = InferSelectModel<typeof obfuscatorPreset>;

export const OBFUSCATOR_PORT_MIN = 51822;
export const OBFUSCATOR_PORT_MAX = 51921;

const name = z
  .string({ message: t('zod.obfuscatorPreset.name') })
  .min(1, t('zod.obfuscatorPreset.name'))
  .max(64, t('zod.obfuscatorPreset.name'))
  .pipe(safeStringRefine);

const extPort = z
  .number({ message: t('zod.obfuscatorPreset.extPort') })
  .int()
  .min(OBFUSCATOR_PORT_MIN, { message: t('zod.obfuscatorPreset.extPort') })
  .max(OBFUSCATOR_PORT_MAX, { message: t('zod.obfuscatorPreset.extPort') });

const sourceIf = z
  .string({ message: t('zod.obfuscatorPreset.sourceIf') })
  .min(1, { message: t('zod.obfuscatorPreset.sourceIf') })
  .max(255)
  .pipe(safeStringRefine);

const target = z
  .string({ message: t('zod.obfuscatorPreset.target') })
  .max(255)
  .refine((v) => v.length === 0 || /^\S+:\d{1,5}$/.test(v), {
    message: t('zod.obfuscatorPreset.target'),
  });

const key = z
  .string({ message: t('zod.obfuscatorPreset.key') })
  .min(3)
  .max(255)
  .pipe(safeStringRefine);

const masking = z.enum(['STUN', 'MEDIA', 'AUTO', 'NONE'], {
  message: t('zod.obfuscatorPreset.masking'),
});

const obfuscateBytes = z
  .number({ message: t('zod.obfuscatorPreset.obfuscateBytes') })
  .int()
  .min(0)
  .max(1024);

const dummy = z
  .number({ message: t('zod.obfuscatorPreset.dummy') })
  .int()
  .min(0)
  .max(1024);

const verbose = z.enum(['error', 'warn', 'info', 'debug', 'trace'], {
  message: t('zod.obfuscatorPreset.verbose'),
});

const clientWgLocalPort = z
  .number({ message: t('zod.obfuscatorPreset.clientWgLocalPort') })
  .int()
  .min(1)
  .max(65535);

export const ObfuscatorPresetCreateSchema = z.object({
  name,
  extPort: extPort.optional(),
  sourceIf: sourceIf.optional(),
  target: target.optional(),
  key: key.optional(),
  masking: masking.optional(),
  obfuscateBytes: obfuscateBytes.optional(),
  dummy: dummy.optional(),
  verbose: verbose.optional(),
  clientWgLocalPort: clientWgLocalPort.optional(),
});

export type ObfuscatorPresetCreateType = z.infer<
  typeof ObfuscatorPresetCreateSchema
>;

export const ObfuscatorPresetUpdateSchema = z
  .object({
    name,
    extPort,
    sourceIf,
    target,
    key,
    masking,
    obfuscateBytes,
    dummy,
    verbose,
    clientWgLocalPort,
  })
  .refine(
    (data) =>
      !(
        data.masking === 'MEDIA' &&
        data.obfuscateBytes > 0 &&
        data.obfuscateBytes < 4
      ),
    {
      message: t('zod.obfuscatorPreset.obfuscateBytesMedia'),
      path: ['obfuscateBytes'],
    }
  );

export type ObfuscatorPresetUpdateType = z.infer<
  typeof ObfuscatorPresetUpdateSchema
>;

const presetId = z.coerce.number({ message: t('zod.obfuscatorPreset.id') });

export const ObfuscatorPresetGetSchema = z.object({
  presetId,
});
