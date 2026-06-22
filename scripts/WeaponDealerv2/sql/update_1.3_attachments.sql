ALTER TABLE `weapon_orders`
    ADD COLUMN IF NOT EXISTS `attachments` JSON NULL DEFAULT NULL AFTER `ammo_price`;
