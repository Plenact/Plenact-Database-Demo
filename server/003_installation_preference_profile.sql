-- Apply once after 002_installation_preferences.sql through the schema-administration workflow.
-- Existing preference rows are retained; new descriptive values are nullable and Excited defaults off.

ALTER TABLE installation_preferences
    ADD COLUMN gender VARCHAR(32) NULL AFTER cat_count,
    ADD COLUMN gender_description VARCHAR(100) NULL AFTER gender,
    ADD COLUMN is_excited TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER gender_description;