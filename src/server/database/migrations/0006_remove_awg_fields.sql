PRAGMA foreign_keys=OFF;--> statement-breakpoint
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
	`firewall_enabled` integer DEFAULT false NOT NULL,
	`obfuscator_ext_port` integer DEFAULT 51822 NOT NULL,
	`obfuscator_key` text DEFAULT '' NOT NULL,
	`obfuscator_masking` text DEFAULT 'STUN' NOT NULL,
	`obfuscator_idle` integer DEFAULT 300 NOT NULL,
	`obfuscator_dummy` integer DEFAULT 10 NOT NULL,
	`server_public_ip_v4` text DEFAULT '' NOT NULL,
	`server_public_ip_v6` text,
	`client_wg_local_port` integer DEFAULT 13255 NOT NULL,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);--> statement-breakpoint
INSERT INTO `__new_interfaces_table`("name", "device", "port", "private_key", "public_key", "ipv4_cidr", "ipv6_cidr", "mtu", "enabled", "firewall_enabled", "obfuscator_ext_port", "obfuscator_key", "obfuscator_masking", "obfuscator_idle", "obfuscator_dummy", "server_public_ip_v4", "server_public_ip_v6", "client_wg_local_port", "created_at", "updated_at") SELECT "name", "device", "port", "private_key", "public_key", "ipv4_cidr", "ipv6_cidr", "mtu", "enabled", "firewall_enabled", "obfuscator_ext_port", "obfuscator_key", "obfuscator_masking", "obfuscator_idle", "obfuscator_dummy", "server_public_ip_v4", "server_public_ip_v6", "client_wg_local_port", "created_at", "updated_at" FROM `interfaces_table`;--> statement-breakpoint
DROP TABLE `interfaces_table`;--> statement-breakpoint
ALTER TABLE `__new_interfaces_table` RENAME TO `interfaces_table`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE UNIQUE INDEX `interfaces_table_port_unique` ON `interfaces_table` (`port`);--> statement-breakpoint
ALTER TABLE `clients_table` DROP COLUMN `j_c`;--> statement-breakpoint
ALTER TABLE `clients_table` DROP COLUMN `j_min`;--> statement-breakpoint
ALTER TABLE `clients_table` DROP COLUMN `j_max`;--> statement-breakpoint
ALTER TABLE `clients_table` DROP COLUMN `i1`;--> statement-breakpoint
ALTER TABLE `clients_table` DROP COLUMN `i2`;--> statement-breakpoint
ALTER TABLE `clients_table` DROP COLUMN `i3`;--> statement-breakpoint
ALTER TABLE `clients_table` DROP COLUMN `i4`;--> statement-breakpoint
ALTER TABLE `clients_table` DROP COLUMN `i5`;--> statement-breakpoint
ALTER TABLE `user_configs_table` DROP COLUMN `default_j_c`;--> statement-breakpoint
ALTER TABLE `user_configs_table` DROP COLUMN `default_j_min`;--> statement-breakpoint
ALTER TABLE `user_configs_table` DROP COLUMN `default_j_max`;--> statement-breakpoint
ALTER TABLE `user_configs_table` DROP COLUMN `default_i1`;--> statement-breakpoint
ALTER TABLE `user_configs_table` DROP COLUMN `default_i2`;--> statement-breakpoint
ALTER TABLE `user_configs_table` DROP COLUMN `default_i3`;--> statement-breakpoint
ALTER TABLE `user_configs_table` DROP COLUMN `default_i4`;--> statement-breakpoint
ALTER TABLE `user_configs_table` DROP COLUMN `default_i5`;
