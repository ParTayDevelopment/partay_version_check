-- Core table for hustle levels and leaderboard
CREATE TABLE IF NOT EXISTS `drug_selling_skills` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `user` VARCHAR(64) NOT NULL,
    `name` VARCHAR(64) NOT NULL,
    `levelpoints` INT NOT NULL DEFAULT 0,
    `rewarded_level` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user` (`user`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
