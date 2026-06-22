CREATE TABLE IF NOT EXISTS `weapon_trade_ins` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `store_id` VARCHAR(64) NOT NULL,
    `buyer_identifier` VARCHAR(64) NOT NULL,
    `employee_identifier` VARCHAR(64) NOT NULL,
    `employee_name` VARCHAR(128) NOT NULL,
    `item` VARCHAR(64) NOT NULL,
    `label` VARCHAR(128) NOT NULL,
    `serial` VARCHAR(64) NULL DEFAULT NULL,
    `slot` INT UNSIGNED NULL DEFAULT NULL,
    `value` INT UNSIGNED NOT NULL DEFAULT 0,
    `registered` TINYINT(1) NOT NULL DEFAULT 0,
    `owned` TINYINT(1) NOT NULL DEFAULT 0,
    `primary_order_id` INT UNSIGNED NULL DEFAULT NULL,
    `order_ids` JSON NULL DEFAULT NULL,
    `metadata` JSON NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_weapon_trade_ins_buyer` (`buyer_identifier`),
    KEY `idx_weapon_trade_ins_primary_order` (`primary_order_id`),
    KEY `idx_weapon_trade_ins_serial` (`serial`),
    KEY `idx_weapon_trade_ins_store` (`store_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `weapon_trade_ins`
    ADD COLUMN IF NOT EXISTS `primary_order_id` INT UNSIGNED NULL DEFAULT NULL AFTER `owned`;
