CREATE TABLE IF NOT EXISTS `partay_airlines` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(80) NOT NULL,
    `code` VARCHAR(12) NOT NULL,
    `owner_citizenid` VARCHAR(64) DEFAULT NULL,
    `balance` INT NOT NULL DEFAULT 0,
    `reputation` INT NOT NULL DEFAULT 50,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_partay_airlines_code` (`code`)
);

CREATE TABLE IF NOT EXISTS `partay_airline_flights` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `flight_number` VARCHAR(20) NOT NULL,
    `airline_id` INT NOT NULL,
    `pilot_citizenid` VARCHAR(64) DEFAULT NULL,
    `aircraft_net_id` INT DEFAULT NULL,
    `aircraft_model` VARCHAR(40) DEFAULT NULL,
    `route_id` VARCHAR(80) NOT NULL,
    `departure_airport` VARCHAR(80) NOT NULL,
    `arrival_airport` VARCHAR(80) NOT NULL,
    `gate` VARCHAR(20) NOT NULL,
    `status` VARCHAR(32) NOT NULL DEFAULT 'scheduled',
    `departure_time` INT NOT NULL,
    `started_at` INT DEFAULT NULL,
    `landed_at` INT DEFAULT NULL,
    `completed_at` INT DEFAULT NULL,
    `ticket_revenue` INT NOT NULL DEFAULT 0,
    `pilot_payout` INT NOT NULL DEFAULT 0,
    `airline_profit` INT NOT NULL DEFAULT 0,
    `flight_score` INT NOT NULL DEFAULT 0,
    `manifest` LONGTEXT DEFAULT NULL,
    `route_progress` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_partay_airline_flights_number` (`flight_number`),
    KEY `idx_partay_airline_flights_status` (`status`),
    KEY `idx_partay_airline_flights_route` (`route_id`)
);

CREATE TABLE IF NOT EXISTS `partay_airline_tickets` (
    `id` INT NOT NULL AUTO_INCREMENT,
    `flight_id` INT NOT NULL,
    `flight_number` VARCHAR(20) NOT NULL,
    `citizenid` VARCHAR(64) NOT NULL,
    `passenger_name` VARCHAR(100) NOT NULL,
    `ticket_class` VARCHAR(32) NOT NULL,
    `seat` VARCHAR(8) NOT NULL,
    `gate` VARCHAR(20) NOT NULL,
    `price` INT NOT NULL DEFAULT 0,
    `status` VARCHAR(32) NOT NULL DEFAULT 'ticketed',
    `metadata` LONGTEXT DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_partay_airline_tickets_flight` (`flight_id`),
    KEY `idx_partay_airline_tickets_citizenid` (`citizenid`)
);

CREATE TABLE IF NOT EXISTS `partay_airports` (
    `id` VARCHAR(80) NOT NULL,
    `label` VARCHAR(120) NOT NULL,
    `tower` VARCHAR(120) DEFAULT NULL,
    `data` LONGTEXT NOT NULL,
    `updated_by` VARCHAR(64) DEFAULT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
);
