-- ===========================================
--  Animal Farming SQL Setup
-- ===========================================

-- 🏡 Farmlot Ownership
CREATE TABLE IF NOT EXISTS `animal_farmlots` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `lot_type` VARCHAR(20) NOT NULL,          -- cow / pig / chicken
    `label` VARCHAR(100) DEFAULT NULL,        -- custom name for the lot
    `coords` LONGTEXT NOT NULL,               -- json coords (vector4)
    `bounds` LONGTEXT DEFAULT NULL,           -- optional boundaries
    `price` INT DEFAULT 0,                    -- purchase price
    `purchased_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX (`citizenid`)
);

-- 🐄 Livestock Data
CREATE TABLE IF NOT EXISTS `animal_livestock` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `owner_cid` VARCHAR(50) NOT NULL,
    `lot_id` INT NOT NULL,
    `animal_type` VARCHAR(20) NOT NULL,       -- cow / pig / chicken
    `gender` ENUM('male','female') NOT NULL,
    `health` FLOAT DEFAULT 100,
    `hunger` FLOAT DEFAULT 100,
    `thirst` FLOAT DEFAULT 100,
    `last_fed` TIMESTAMP NULL DEFAULT NULL,
    `last_watered` TIMESTAMP NULL DEFAULT NULL,
    `last_product` TIMESTAMP NULL DEFAULT NULL, -- last time item produced
    `is_dead` TINYINT(1) DEFAULT 0,
    `spawned` TINYINT(1) DEFAULT 0,           -- is currently spawned
    `coords` LONGTEXT NULL,                   -- spawn position (JSON vec3)
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX (`owner_cid`),
    INDEX (`lot_id`),
    FOREIGN KEY (`lot_id`) REFERENCES `animal_farmlots`(`id`) ON DELETE CASCADE
);

-- 🚰 Water Troughs
CREATE TABLE IF NOT EXISTS `animal_water_troughs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `lot_id` INT NOT NULL,
    `coords` LONGTEXT NOT NULL,               -- json coords
    `water_level` FLOAT DEFAULT 100,
    `last_refilled` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX (`lot_id`),
    FOREIGN KEY (`lot_id`) REFERENCES `animal_farmlots`(`id`) ON DELETE CASCADE
);

-- 💰 Transaction Log
CREATE TABLE IF NOT EXISTS `animal_transactions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `type` ENUM('buy_lot', 'buy_animal', 'sell_product', 'butcher') NOT NULL,
    `ref_id` INT DEFAULT NULL,                -- lot_id or animal_id
    `animal_type` VARCHAR(20) DEFAULT NULL,
    `amount` INT DEFAULT 0,                   -- money amount
    `meta` LONGTEXT DEFAULT NULL,             -- additional data (JSON)
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX (`citizenid`)
);

-- 📊 Production Log
CREATE TABLE IF NOT EXISTS `animal_production_log` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `animal_id` INT NOT NULL,
    `owner_cid` VARCHAR(50) NOT NULL,
    `product` VARCHAR(50) NOT NULL,           -- item name
    `amount` INT DEFAULT 1,
    `quality` INT DEFAULT 100,               -- quality percentage
    `at_health` FLOAT DEFAULT 100,           -- animal health at time of production
    `at_hunger` FLOAT DEFAULT 100,           -- animal hunger at time of production
    `at_thirst` FLOAT DEFAULT 100,           -- animal thirst at time of production
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX (`animal_id`),
    INDEX (`owner_cid`)
);

-- 💀 Death Log
CREATE TABLE IF NOT EXISTS `animal_death_log` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `animal_id` INT NOT NULL,
    `owner_cid` VARCHAR(50) NOT NULL,
    `cause` ENUM('neglect', 'butchered', 'old_age', 'disease') NOT NULL,
    `by_cid` VARCHAR(50) DEFAULT NULL,        -- who caused the death (for butchering)
    `yields_json` LONGTEXT DEFAULT NULL,      -- what was gained from death
    `skill_level` INT DEFAULT 0,             -- butchering skill level
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX (`animal_id`),
    INDEX (`owner_cid`)
);

-- 📝 Activity Log (Optional - for detailed tracking)
CREATE TABLE IF NOT EXISTS `animal_activity_log` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `animal_id` INT NOT NULL,
    `owner_cid` VARCHAR(50) NOT NULL,
    `action` VARCHAR(50) NOT NULL,            -- feed, water, collect, etc.
    `details` LONGTEXT DEFAULT NULL,          -- JSON details
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX (`animal_id`),
    INDEX (`owner_cid`)
);

-- ===========================================
-- Suggested Items for ox_inventory
-- (Make sure these exist in your items table)
-- ===========================================

-- 🥕 Feeding
INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `type`, `image`) VALUES
('animal_feed', 'Animal Feed', 100, 'item', 'animal_feed.png');

-- 🔪 Tools
INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `type`, `image`) VALUES
('knife', 'Butcher Knife', 200, 'item', 'knife.png');

-- 🥩 Products
INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `type`, `image`) VALUES
('raw_meat', 'Raw Meat', 300, 'item', 'raw_meat.png'),
('raw_pork', 'Raw Pork', 300, 'item', 'raw_pork.png'),
('milk', 'Fresh Milk', 200, 'item', 'milk.png'),
('eggs', 'Chicken Eggs', 100, 'item', 'eggs.png');