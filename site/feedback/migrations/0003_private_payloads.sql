-- Apply after 0002 to the original, empty feedback database only.
-- A nonempty database needs an explicit migration that removes historical content.
CREATE TABLE migration_0003_empty_guard (count INTEGER CHECK(count=0));
INSERT INTO migration_0003_empty_guard SELECT COUNT(*) FROM submissions;
ALTER TABLE submissions ADD COLUMN payload_id TEXT;
ALTER TABLE submissions DROP COLUMN message;
ALTER TABLE submissions DROP COLUMN contact_email;
ALTER TABLE submissions DROP COLUMN reason_codes;
ALTER TABLE submissions DROP COLUMN screened_text;
ALTER TABLE submissions DROP COLUMN review_text;
ALTER TABLE submissions DROP COLUMN draft_json;
ALTER TABLE submissions DROP COLUMN approval_json;
CREATE TABLE payload_generations (
 id TEXT PRIMARY KEY, submission_id TEXT NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
 sha256 TEXT NOT NULL, bytes INTEGER NOT NULL, created_at INTEGER NOT NULL
);
DROP TABLE migration_0003_empty_guard;
