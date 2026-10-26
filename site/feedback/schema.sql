PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS submissions (
 id TEXT PRIMARY KEY, source TEXT NOT NULL CHECK(source IN ('web','native','email')), category TEXT NOT NULL,
 identity_hash TEXT NOT NULL, idempotency_key TEXT NOT NULL, fingerprint TEXT NOT NULL, token_hash TEXT NOT NULL,
 message TEXT NOT NULL, contact_email TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'reserved'
 CHECK(status IN ('reserved','received','scanning','screened','held','rejected')),
 created_at INTEGER NOT NULL, reservation_expires_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
 queued INTEGER NOT NULL DEFAULT 0, scan_lease_until INTEGER, reason_codes TEXT NOT NULL DEFAULT '[]', scan_metadata TEXT,
 screened_text TEXT, draft_json TEXT, draft_status TEXT, notified INTEGER NOT NULL DEFAULT 0,
 UNIQUE(identity_hash,idempotency_key)
);
CREATE TABLE IF NOT EXISTS files (
 id TEXT PRIMARY KEY, submission_id TEXT NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
 content_type TEXT NOT NULL, bytes INTEGER NOT NULL, sha256 TEXT NOT NULL, raw_key TEXT NOT NULL,
 role TEXT NOT NULL DEFAULT 'attachment', ordinal INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','uploading','uploaded'))
);
CREATE TABLE IF NOT EXISTS derivatives (
 id TEXT PRIMARY KEY, submission_id TEXT NOT NULL REFERENCES submissions(id) ON DELETE CASCADE,
 name TEXT NOT NULL, storage_key TEXT NOT NULL, bytes INTEGER NOT NULL, sha256 TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS counters (key TEXT PRIMARY KEY, value INTEGER NOT NULL, expires_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS budget (month TEXT PRIMARY KEY, reserved_microdollars INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS audit (id INTEGER PRIMARY KEY, submission_id TEXT, action TEXT NOT NULL, at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS submissions_expiry ON submissions(expires_at);
CREATE INDEX IF NOT EXISTS submissions_outbox ON submissions(status,queued);
CREATE INDEX IF NOT EXISTS files_submission ON files(submission_id);
CREATE INDEX IF NOT EXISTS derivatives_submission ON derivatives(submission_id);
