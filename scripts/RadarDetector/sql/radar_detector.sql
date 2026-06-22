CREATE TABLE IF NOT EXISTS `radar_detector_vehicles` (
    `plate` VARCHAR(16) NOT NULL,
    `installer` VARCHAR(80) NULL,
    `metadata` LONGTEXT NULL,
    `installed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`plate`)
);
