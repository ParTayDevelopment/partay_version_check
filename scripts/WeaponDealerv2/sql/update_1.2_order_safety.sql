ALTER TABLE `weapon_orders`
    ADD COLUMN IF NOT EXISTS `ammo_item` VARCHAR(64) NULL DEFAULT NULL AFTER `price`,
    ADD COLUMN IF NOT EXISTS `ammo_count` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `ammo_item`,
    ADD COLUMN IF NOT EXISTS `ammo_price` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `ammo_count`;

ALTER TABLE `weapon_orders`
    ADD INDEX IF NOT EXISTS `idx_weapon_orders_ready` (`status`, `ready_at`),
    ADD INDEX IF NOT EXISTS `idx_weapon_orders_buyer_status` (`buyer_identifier`, `status`);
