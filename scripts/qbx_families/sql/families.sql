CREATE TABLE IF NOT EXISTS `family_members` (
    `citizenid` VARCHAR(64) NOT NULL,
    `family` VARCHAR(64) NOT NULL,
    `role` VARCHAR(64) NOT NULL,
    `invited_by` VARCHAR(64) NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`),
    KEY `idx_family_members_family` (`family`),
    KEY `idx_family_members_role` (`role`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `family_audit_logs` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `action` VARCHAR(80) NOT NULL,
    `actor_citizenid` VARCHAR(64) NULL DEFAULT NULL,
    `target_citizenid` VARCHAR(64) NULL DEFAULT NULL,
    `family` VARCHAR(64) NULL DEFAULT NULL,
    `payload` LONGTEXT NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_family_audit_action` (`action`),
    KEY `idx_family_audit_family` (`family`),
    KEY `idx_family_audit_target` (`target_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `family_heads` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `family` VARCHAR(64) NOT NULL,
    `citizenid` VARCHAR(64) NULL DEFAULT NULL,
    `discord` VARCHAR(32) NULL DEFAULT NULL,
    `assigned_by` VARCHAR(64) NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_family_heads_family` (`family`),
    KEY `idx_family_heads_citizenid` (`citizenid`),
    KEY `idx_family_heads_discord` (`discord`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `family_points` (
    `family` VARCHAR(64) NOT NULL,
    `available_points` INT NOT NULL DEFAULT 0,
    `total_points` INT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`family`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `family_reward_redemptions` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `family` VARCHAR(64) NOT NULL,
    `reward_id` VARCHAR(80) NOT NULL,
    `redeemed_by` VARCHAR(64) NOT NULL,
    `cost` INT NOT NULL DEFAULT 0,
    `payload` LONGTEXT NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_family_reward_family` (`family`),
    KEY `idx_family_reward_reward` (`reward_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `family_events` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `family` VARCHAR(64) NOT NULL,
    `name` VARCHAR(80) NOT NULL,
    `created_by` VARCHAR(64) NOT NULL,
    `coords` LONGTEXT NOT NULL,
    `preset` VARCHAR(50) NULL DEFAULT NULL,
    `radius` FLOAT NOT NULL DEFAULT 35,
    `points_per_tick` INT NOT NULL DEFAULT 10,
    `status` VARCHAR(20) NOT NULL DEFAULT 'active',
    `started_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `starts_at` TIMESTAMP NULL DEFAULT NULL,
    `ended_at` TIMESTAMP NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_family_events_family` (`family`),
    KEY `idx_family_events_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `family_event_templates` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `family` VARCHAR(64) NOT NULL,
    `name` VARCHAR(80) NOT NULL,
    `created_by` VARCHAR(64) NOT NULL,
    `coords` LONGTEXT NOT NULL,
    `preset` VARCHAR(50) NULL DEFAULT NULL,
    `radius` FLOAT NOT NULL DEFAULT 35,
    `points_per_tick` INT NOT NULL DEFAULT 10,
    `banner_url` LONGTEXT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_family_event_templates_family` (`family`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `family_event_shares` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `template_id` INT UNSIGNED NOT NULL,
    `owner_family` VARCHAR(64) NOT NULL,
    `shared_with_family` VARCHAR(64) NOT NULL,
    `shared_by` VARCHAR(64) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_family_event_share` (`template_id`, `shared_with_family`),
    KEY `idx_family_event_shares_owner` (`owner_family`),
    KEY `idx_family_event_shares_shared_with` (`shared_with_family`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
