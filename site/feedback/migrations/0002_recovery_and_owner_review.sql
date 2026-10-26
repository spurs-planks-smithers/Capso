-- Apply once only to a database initialized with the original feedback schema.
-- A new database uses schema.sql instead and does not need this upgrade.
ALTER TABLE submissions ADD COLUMN notification_lease_until INTEGER;
ALTER TABLE submissions ADD COLUMN notification_claim TEXT;
ALTER TABLE submissions ADD COLUMN scan_claim TEXT;
ALTER TABLE submissions ADD COLUMN review_text TEXT;
ALTER TABLE submissions ADD COLUMN review_proof TEXT;
ALTER TABLE submissions ADD COLUMN review_fingerprint TEXT;
ALTER TABLE submissions ADD COLUMN review_policy TEXT;
ALTER TABLE submissions ADD COLUMN review_expires_at INTEGER;
ALTER TABLE submissions ADD COLUMN approval_json TEXT;
ALTER TABLE files ADD COLUMN upload_lease_until INTEGER;
ALTER TABLE files ADD COLUMN upload_claim TEXT;
ALTER TABLE derivatives ADD COLUMN review_only INTEGER NOT NULL DEFAULT 0;
ALTER TABLE derivatives ADD COLUMN scan_claim TEXT;
CREATE TABLE upload_attempts (
 id TEXT PRIMARY KEY,
 file_id TEXT NOT NULL REFERENCES files(id) ON DELETE CASCADE,
 submission_id TEXT NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
 raw_key TEXT NOT NULL
);
