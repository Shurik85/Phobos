ALTER TABLE `warp_table` ADD `preshared_key` text DEFAULT '' NOT NULL;
--> statement-breakpoint
ALTER TABLE `warp_table` ADD `dns` text DEFAULT '' NOT NULL;
--> statement-breakpoint
ALTER TABLE `warp_table` ADD `persistent_keepalive` integer DEFAULT 25 NOT NULL;
