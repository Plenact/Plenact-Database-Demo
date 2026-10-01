-- Apply once through the separate schema-administration workflow.
-- Do not rerun 001_initial.sql against the existing database.

CREATE TABLE installation_preferences (
    installation_id CHAR(36) CHARACTER SET ascii
        COLLATE ascii_bin NOT NULL,
    favorite_food VARCHAR(255) NOT NULL,
    cat_count INT UNSIGNED NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (installation_id)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;