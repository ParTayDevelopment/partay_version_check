CREATE TABLE IF NOT EXISTS `weapon_part_orders` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `store_id` VARCHAR(64) NOT NULL,
    `employee_identifier` VARCHAR(64) NOT NULL,
    `employee_name` VARCHAR(128) NOT NULL,
    `payment_source` VARCHAR(16) NOT NULL,
    `total` INT UNSIGNED NOT NULL DEFAULT 0,
    `items` JSON NOT NULL,
    `status` ENUM('pending_delivery', 'delivered', 'cancelled') NOT NULL DEFAULT 'pending_delivery',
    `delivery_at` DATETIME NOT NULL,
    `delivered_at` DATETIME NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_weapon_part_orders_store_status` (`store_id`, `status`),
    KEY `idx_weapon_part_orders_delivery` (`status`, `delivery_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
