import type { InferSelectModel } from 'drizzle-orm';
import z from 'zod';
import type { userConfig } from './schema';

export type UserConfigType = InferSelectModel<typeof userConfig>;

const host = z
  .string({ message: t('zod.userConfig.host') })
  .min(1, t('zod.userConfig.host'))
  .pipe(safeStringRefine);

export const UserConfigSetupSchema = z.object({
  host: host,
});

export type UserConfigUpdateType = Omit<
  UserConfigType,
  'id' | 'createdAt' | 'updatedAt'
>;

export const UserConfigUpdateSchema = schemaForType<UserConfigUpdateType>()(
  z.object({
    defaultMtu: MtuSchema,
    defaultPersistentKeepalive: PersistentKeepaliveSchema,
    defaultDns: DnsSchema,
    defaultAllowedIps: AllowedIpsSchema,
    host: host,
  })
);
