ALTER TABLE `weapon_orders`
    MODIFY COLUMN `status` ENUM('pending_assembly', 'approved', 'ready', 'picked_up', 'cancelled', 'revoked', 'confiscated', 'transferred') NOT NULL DEFAULT 'approved',
    ADD COLUMN IF NOT EXISTS `payment_method` VARCHAR(16) NULL DEFAULT NULL AFTER `license_id`,
    ADD COLUMN IF NOT EXISTS `assembled_by` VARCHAR(64) NULL DEFAULT NULL AFTER `picked_up_at`,
    ADD COLUMN IF NOT EXISTS `assembled_by_name` VARCHAR(128) NULL DEFAULT NULL AFTER `assembled_by`,
    ADD COLUMN IF NOT EXISTS `assembled_at` DATETIME NULL DEFAULT NULL AFTER `assembled_by_name`,
    ADD COLUMN IF NOT EXISTS `refunded_by` VARCHAR(64) NULL DEFAULT NULL AFTER `assembled_at`,
    ADD COLUMN IF NOT EXISTS `refunded_by_name` VARCHAR(128) NULL DEFAULT NULL AFTER `refunded_by`,
    ADD COLUMN IF NOT EXISTS `refunded_at` DATETIME NULL DEFAULT NULL AFTER `refunded_by_name`;
