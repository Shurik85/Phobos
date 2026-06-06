PRAGMA foreign_keys=OFF;
--> statement-breakpoint
CREATE TABLE `__new_obfuscator_presets_table` (
  `id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  `name` text NOT NULL,
  `is_default` integer NOT NULL DEFAULT 0,
  `ext_port` integer NOT NULL,
  `source_if` text NOT NULL DEFAULT '0.0.0.0',
  `target` text,
  `key` text NOT NULL,
  `masking` text NOT NULL DEFAULT 'STUN',
  `obfuscate_bytes` integer NOT NULL DEFAULT 0,
  `dummy` integer NOT NULL DEFAULT 40,
  `verbose` text NOT NULL DEFAULT 'error',
  `client_wg_local_port` integer NOT NULL DEFAULT 13255,
  `created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
  `updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);
--> statement-breakpoint
INSERT INTO `__new_obfuscator_presets_table`
  (`id`, `name`, `is_default`, `ext_port`, `source_if`, `target`, `key`,
   `masking`, `obfuscate_bytes`, `dummy`, `verbose`, `client_wg_local_port`,
   `created_at`, `updated_at`)
SELECT
  `id`, `name`, `is_default`, `ext_port`, '0.0.0.0', NULL, `key`,
  `masking`, 0, `dummy`, 'info', `client_wg_local_port`,
  `created_at`, `updated_at`
FROM `obfuscator_presets_table`;
--> statement-breakpoint
DROP TABLE `obfuscator_presets_table`;
--> statement-breakpoint
ALTER TABLE `__new_obfuscator_presets_table` RENAME TO `obfuscator_presets_table`;
--> statement-breakpoint
CREATE UNIQUE INDEX `obfuscator_presets_table_name_unique` ON `obfuscator_presets_table` (`name`);
--> statement-breakpoint
CREATE UNIQUE INDEX `obfuscator_presets_table_ext_port_unique` ON `obfuscator_presets_table` (`ext_port`);
--> statement-breakpoint
CREATE UNIQUE INDEX `uq_default_preset` ON `obfuscator_presets_table` (`is_default`) WHERE `is_default` = 1;
--> statement-breakpoint
PRAGMA foreign_keys=ON;
