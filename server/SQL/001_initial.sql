-- Run once in the empty plenact_dev database.
-- All DATETIME values in this application represent UTC.

CREATE TABLE app_config (
    config_key VARCHAR(64) NOT NULL,
    config_value VARCHAR(255) NOT NULL,
    version INT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (config_key)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;

CREATE TABLE notices (
    notice_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    message VARCHAR(500) NOT NULL,
    is_active TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (notice_id)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;

CREATE TABLE installation_status (
    installation_id CHAR(36) CHARACTER SET ascii
        COLLATE ascii_bin NOT NULL,
    report_sequence BIGINT UNSIGNED NOT NULL,
    app_version VARCHAR(32) NOT NULL,
    reported_state VARCHAR(64) NOT NULL,
    received_at DATETIME(6) NOT NULL,
    PRIMARY KEY (installation_id)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;

INSERT INTO app_config (config_key, config_value, version)
VALUES ('welcome_message', 'Hello from the Plenact database!', 1);

INSERT INTO notices (message, is_active)
VALUES ('Development connection test: welcome aboard.', 1);