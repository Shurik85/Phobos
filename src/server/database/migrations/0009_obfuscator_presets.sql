CREATE TABLE `obfuscator_presets_table` (
  `id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  `name` text NOT NULL,
  `is_default` integer NOT NULL DEFAULT 0,
  `ext_port` integer NOT NULL,
  `key` text NOT NULL,
  `masking` text NOT NULL DEFAULT 'STUN',
  `idle` integer NOT NULL DEFAULT 300,
  `dummy` integer NOT NULL DEFAULT 10,
  `client_wg_local_port` integer NOT NULL DEFAULT 13255,
  `created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
  `updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `obfuscator_presets_table_name_unique` ON `obfuscator_presets_table` (`name`);
--> statement-breakpoint
CREATE UNIQUE INDEX `obfuscator_presets_table_ext_port_unique` ON `obfuscator_presets_table` (`ext_port`);
--> statement-breakpoint
CREATE UNIQUE INDEX `uq_default_preset` ON `obfuscator_presets_table` (`is_default`) WHERE `is_default` = 1;
--> statement-breakpoint
INSERT INTO `obfuscator_presets_table`
  (`id`, `name`, `is_default`, `ext_port`, `key`, `masking`, `idle`, `dummy`, `client_wg_local_port`)
SELECT
  1,
  'default',
  1,
  CASE WHEN `obfuscator_ext_port` BETWEEN 51822 AND 51921 THEN `obfuscator_ext_port` ELSE 51822 END,
  CASE WHEN length(coalesce(`obfuscator_key`, '')) > 0 THEN `obfuscator_key` ELSE 'changeme' END,
  coalesce(`obfuscator_masking`, 'STUN'),
  coalesce(`obfuscator_idle`, 300),
  coalesce(`obfuscator_dummy`, 10),
  coalesce(`client_wg_local_port`, 13255)
FROM `interfaces_table`
WHERE `name` = 'wg0';
--> statement-breakpoint
PRAGMA foreign_keys=OFF;
--> statement-breakpoint
ALTER TABLE `clients_table` ADD COLUMN `preset_id` integer REFERENCES `obfuscator_presets_table`(`id`) ON UPDATE cascade ON DELETE set null;
--> statement-breakpoint
CREATE TABLE `__new_interfaces_table` (
  `name` text PRIMARY KEY NOT NULL,
  `device` text NOT NULL,
  `port` integer NOT NULL,
  `private_key` text NOT NULL,
  `public_key` text NOT NULL,
  `ipv4_cidr` text NOT NULL,
  `ipv6_cidr` text NOT NULL,
  `mtu` integer NOT NULL,
  `enabled` integer NOT NULL,
  `firewall_enabled` integer DEFAULT 0 NOT NULL,
  `server_public_ip_v4` text DEFAULT '' NOT NULL,
  `server_public_ip_v6` text,
  `created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
  `updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);
--> statement-breakpoint
INSERT INTO `__new_interfaces_table`
  (`name`, `device`, `port`, `private_key`, `public_key`,
   `ipv4_cidr`, `ipv6_cidr`, `mtu`, `enabled`, `firewall_enabled`,
   `server_public_ip_v4`, `server_public_ip_v6`,
   `created_at`, `updated_at`)
SELECT
  `name`, `device`, `port`, `private_key`, `public_key`,
  `ipv4_cidr`, `ipv6_cidr`, `mtu`, `enabled`, `firewall_enabled`,
  `server_public_ip_v4`, `server_public_ip_v6`,
  `created_at`, `updated_at`
FROM `interfaces_table`;
--> statement-breakpoint
DROP TABLE `interfaces_table`;
--> statement-breakpoint
ALTER TABLE `__new_interfaces_table` RENAME TO `interfaces_table`;
--> statement-breakpoint
CREATE UNIQUE INDEX `interfaces_table_port_unique` ON `interfaces_table` (`port`);
--> statement-breakpoint
PRAGMA foreign_keys=ON;
