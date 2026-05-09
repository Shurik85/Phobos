UPDATE `interfaces_table` SET `port` = 51820 WHERE 1 = 1;--> statement-breakpoint
ALTER TABLE `user_configs_table` DROP COLUMN `port`;
