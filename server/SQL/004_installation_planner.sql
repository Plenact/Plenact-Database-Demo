-- Apply once after the existing preference migrations through the schema-administration workflow.
-- Planner data is stored as one versioned JSON snapshot per configured demo installation.

CREATE TABLE installation_planner (
    installation_id CHAR(36) CHARACTER SET ascii
        COLLATE ascii_bin NOT NULL,
    planner_document JSON NOT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (installation_id)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;