-- One row per GET of /download. No IP address and no raw user agent.
-- at: UTC time (ISO 8601). is_bot: 1 when the user agent matches a bot or
-- link-preview pattern in src/worker.js.
CREATE TABLE IF NOT EXISTS downloads (
  id INTEGER PRIMARY KEY,
  at TEXT NOT NULL,
  version TEXT NOT NULL,
  country TEXT,
  is_bot INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS downloads_at ON downloads (at);
