ALTER TABLE `interfaces_table` ADD `egress_mode` text DEFAULT 'wan' NOT NULL;
--> statement-breakpoint
CREATE TABLE `warp_table` (
  `id` integer PRIMARY KEY DEFAULT 1,
  `access_token` text DEFAULT '' NOT NULL,
  `device_id` text DEFAULT '' NOT NULL,
  `license_key` text DEFAULT '' NOT NULL,
  `private_key` text DEFAULT '' NOT NULL,
  `client_id` text DEFAULT '' NOT NULL,
  `peer_public_key` text DEFAULT '' NOT NULL,
  `endpoint` text DEFAULT 'engage.cloudflareclient.com:2408' NOT NULL,
  `address_v4` text DEFAULT '' NOT NULL,
  `address_v6` text DEFAULT '' NOT NULL,
  `mtu` integer DEFAULT 1280 NOT NULL,
  `update_interval_days` integer DEFAULT 0 NOT NULL,
  `last_update_at` text,
  `created_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL,
  `updated_at` text DEFAULT (CURRENT_TIMESTAMP) NOT NULL
);
--> statement-breakpoint
INSERT INTO `warp_table` (`id`) VALUES (1);
