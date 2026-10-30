PRAGMA foreign_keys=ON;
CREATE TABLE users (
  id TEXT PRIMARY KEY, identity_hash TEXT NOT NULL UNIQUE,
  enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0,1)),
  monthly_limit INTEGER NOT NULL CHECK(monthly_limit BETWEEN 0 AND 25000000)
);
-- A verified Access email can bind its subject only after an operator invites it.
CREATE TABLE invitations (
  email_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL UNIQUE,
  enabled INTEGER NOT NULL CHECK(enabled IN(0,1)),
  monthly_limit INTEGER NOT NULL CHECK(monthly_limit BETWEEN 0 AND 25000000)
);
CREATE TABLE codes (
  hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
  challenge TEXT NOT NULL, expires INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0 CHECK(used IN(0,1))
);
CREATE TABLE families (id TEXT PRIMARY KEY, revoked INTEGER NOT NULL DEFAULT 0);
CREATE TABLE sessions (
  hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
  issuer TEXT NOT NULL, audience TEXT NOT NULL, family TEXT NOT NULL, expires INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE requests (
  request_id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
  digest TEXT NOT NULL, month TEXT NOT NULL CHECK(month GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'),
  reserved INTEGER NOT NULL CHECK(reserved=2753), created INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN('pending','complete','uncertain')),
  finished_month TEXT, input_tokens INTEGER, output_tokens INTEGER, latency_ms INTEGER
);
CREATE INDEX request_month ON requests(month,user_id);
CREATE TRIGGER reserve BEFORE INSERT ON requests BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.user_id AND enabled=1) THEN RAISE(ABORT,'denied') END;
 SELECT CASE WHEN COALESCE((SELECT SUM(reserved) FROM requests WHERE month>=NEW.month OR (month<NEW.month AND (status IN('pending','uncertain') OR finished_month>=NEW.month))),0)+NEW.reserved>25000000 THEN RAISE(ABORT,'global_limit') END;
 SELECT CASE WHEN COALESCE((SELECT SUM(reserved) FROM requests WHERE user_id=NEW.user_id AND (month>=NEW.month OR (month<NEW.month AND (status IN('pending','uncertain') OR finished_month>=NEW.month)))),0)+NEW.reserved>(SELECT monthly_limit FROM users WHERE id=NEW.user_id) THEN RAISE(ABORT,'user_limit') END;
 SELECT CASE WHEN (SELECT COUNT(*) FROM requests WHERE user_id=NEW.user_id AND created>NEW.created-60)>=6 THEN RAISE(ABORT,'rate_limit') END;
END;
-- Reservations are permanent accounting records, including unknown upstream outcomes.
CREATE TRIGGER immutable_reservation BEFORE UPDATE OF request_id,user_id,digest,month,reserved,created ON requests BEGIN SELECT RAISE(ABORT,'immutable'); END;
CREATE TRIGGER no_refunds BEFORE DELETE ON requests BEGIN SELECT RAISE(ABORT,'no_refunds'); END;

CREATE TABLE refresh_tokens (
 hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), family TEXT NOT NULL,
 expires INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0, revoked INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX refresh_family ON refresh_tokens(family);
