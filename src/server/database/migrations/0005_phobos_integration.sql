ALTER TABLE `interfaces_table` ADD `obfuscator_ext_port` integer DEFAULT 51822 NOT NULL;--> statement-breakpoint
ALTER TABLE `interfaces_table` ADD `obfuscator_key` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `interfaces_table` ADD `obfuscator_masking` text DEFAULT 'STUN' NOT NULL;--> statement-breakpoint
ALTER TABLE `interfaces_table` ADD `obfuscator_idle` integer DEFAULT 300 NOT NULL;--> statement-breakpoint
ALTER TABLE `interfaces_table` ADD `obfuscator_dummy` integer DEFAULT 10 NOT NULL;--> statement-breakpoint
ALTER TABLE `interfaces_table` ADD `server_public_ip_v4` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `interfaces_table` ADD `server_public_ip_v6` text;--> statement-breakpoint
ALTER TABLE `interfaces_table` ADD `client_wg_local_port` integer DEFAULT 13255 NOT NULL;--> statement-breakpoint
DROP TABLE `one_time_links_table`;--> statement-breakpoint
CREATE TABLE `install_links_table` (
	`id` integer PRIMARY KEY NOT NULL,
	`token` text NOT NULL,
	`expires_at` text NOT NULL,
	`created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	`updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
	FOREIGN KEY (`id`) REFERENCES `clients_table`(`id`) ON UPDATE cascade ON DELETE cascade
);--> statement-breakpoint
CREATE UNIQUE INDEX `install_links_table_token_unique` ON `install_links_table` (`token`);
