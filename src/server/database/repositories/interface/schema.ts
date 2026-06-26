import { sql, relations } from 'drizzle-orm';
import { int, sqliteTable, text } from 'drizzle-orm/sqlite-core';

import { userConfig, hooks } from '../../schema';

export const wgInterface = sqliteTable('interfaces_table', {
  name: text().primaryKey(),
  device: text().notNull(),
  port: int().notNull().unique(),
  privateKey: text('private_key').notNull(),
  publicKey: text('public_key').notNull(),
  ipv4Cidr: text('ipv4_cidr').notNull(),
  ipv6Cidr: text('ipv6_cidr').notNull(),
  mtu: int().notNull(),
  enabled: int({ mode: 'boolean' }).notNull(),
  firewallEnabled: int('firewall_enabled', { mode: 'boolean' })
    .notNull()
    .default(false),
  egressMode: text('egress_mode', { enum: ['wan', 'warp'] })
    .notNull()
    .default('wan'),
  serverPublicIpV4: text('server_public_ip_v4').notNull().default(''),
  serverPublicIpV6: text('server_public_ip_v6'),
  serverPublicDomain: text('server_public_domain'),
  createdAt: text('created_at')
    .notNull()
    .default(sql`(CURRENT_TIMESTAMP)`),
  updatedAt: text('updated_at')
    .notNull()
    .default(sql`(CURRENT_TIMESTAMP)`)
    .$onUpdate(() => sql`(CURRENT_TIMESTAMP)`),
});

export const wgInterfaceRelations = relations(wgInterface, ({ one }) => ({
  hooks: one(hooks, {
    fields: [wgInterface.name],
    references: [hooks.id],
  }),
  userConfig: one(userConfig, {
    fields: [wgInterface.name],
    references: [userConfig.id],
  }),
}));
