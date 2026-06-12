import type { InferSelectModel } from 'drizzle-orm';
import z from 'zod';
import { isIP } from 'is-ip';
import type { warp } from './schema';

export type WarpType = InferSelectModel<typeof warp>;

const wgKey = z
  .string({ message: t('zod.warp.key') })
  .regex(/^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$/, {
    message: t('zod.warp.key'),
  });

const endpoint = z
  .string({ message: t('zod.warp.endpoint') })
  .regex(/^[a-zA-Z0-9.-]+:\d{1,5}$/, { message: t('zod.warp.endpoint') })
  .pipe(safeStringRefine);

const addressV4 = z
  .string({ message: t('zod.warp.addressV4') })
  .refine((v) => isIP(v) && !v.includes(':'), {
    message: t('zod.warp.addressV4'),
  });

const addressV6 = z
  .string({ message: t('zod.warp.addressV6') })
  .refine((v) => isIP(v) && v.includes(':'), {
    message: t('zod.warp.addressV6'),
  });

export const WarpUpdateSchema = z.object({
  privateKey: wgKey,
  peerPublicKey: wgKey,
  endpoint: endpoint,
  addressV4: addressV4,
  addressV6: addressV6,
  mtu: MtuSchema,
});

export type WarpUpdateType = z.infer<typeof WarpUpdateSchema>;

const wgKeyOrEmpty = z.union([z.literal(''), wgKey]);

export const WarpManualSchema = z.object({
  privateKey: wgKey,
  peerPublicKey: wgKey,
  endpoint: endpoint,
  addressV4: addressV4,
  addressV6: z.union([z.literal(''), addressV6]),
  mtu: MtuSchema,
  presharedKey: wgKeyOrEmpty.default(''),
  dns: z.string().default('').pipe(safeStringRefine),
  persistentKeepalive: PersistentKeepaliveSchema.default(25),
});

export type WarpManualType = z.infer<typeof WarpManualSchema>;

export const WarpLicenseSchema = z.object({
  license: z
    .string({ message: t('zod.warp.license') })
    .min(26, { message: t('zod.warp.license') })
    .pipe(safeStringRefine),
});

export const WarpIntervalSchema = z.object({
  updateIntervalDays: z
    .number({ message: t('zod.warp.interval') })
    .int({ message: t('zod.warp.interval') })
    .min(0, { message: t('zod.warp.interval') })
    .max(365, { message: t('zod.warp.interval') }),
});

export type WarpRegistrationType = Pick<
  WarpType,
  | 'accessToken'
  | 'deviceId'
  | 'licenseKey'
  | 'privateKey'
  | 'clientId'
  | 'peerPublicKey'
  | 'endpoint'
  | 'addressV4'
  | 'addressV6'
>;
