import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { digest } from "../src/policy.js";
export function environment() {
  const sql = new DatabaseSync(":memory:");
  sql.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
  const statement = (text, args = []) => ({
    bind(...values) {
      return statement(text, values);
    },
    async first() {
      return sql.prepare(text).get(...args) || null;
    },
    async all() {
      return { results: sql.prepare(text).all(...args) };
    },
    async run() {
      const out = sql.prepare(text).run(...args);
      return { meta: { changes: Number(out.changes) } };
    },
  });
  const DB = {
    prepare: statement,
    async batch(statements) {
      sql.exec("BEGIN");
      try {
        const output = [];
        for (const item of statements) output.push(await item.run());
        sql.exec("COMMIT");
        return output;
      } catch (error) {
        sql.exec("ROLLBACK");
        throw error;
      }
    },
  };
  const bucket = () => {
    const data = new Map(),
      meta = new Map();
    return {
      data,
      meta,
      async put(key, body, options = {}) {
        const existing = meta.get(key),
          condition = options.onlyIf;
        if (
          (condition?.etagDoesNotMatch === "*" && data.has(key)) ||
          (condition?.etagMatches && existing?.etag !== condition.etagMatches)
        )
          return null;
        const bytes =
          typeof body === "string"
            ? new TextEncoder().encode(body)
            : new Uint8Array(body);
        const etag = await digest(bytes);
        data.set(key, bytes);
        meta.set(key, {
          etag,
          customMetadata: options.customMetadata || {},
          uploaded: new Date(),
        });
        return { key, size: bytes.length, ...meta.get(key) };
      },
      async get(key) {
        const value = data.get(key);
        return value
          ? {
              key,
              size: value.length,
              ...meta.get(key),
              arrayBuffer: async () => value.slice().buffer,
              text: async () => new TextDecoder().decode(value),
              body: new Response(value).body,
            }
          : null;
      },
      async delete(keys) {
        for (const key of Array.isArray(keys) ? keys : [keys]) {
          data.delete(key);
          meta.delete(key);
        }
      },
      async list({ prefix = "", cursor, limit = 1000 } = {}) {
        const keys = [...data.keys()]
            .filter(
              (key) => key.startsWith(prefix) && (!cursor || key > cursor),
            )
            .sort(),
          selected = keys.slice(0, limit);
        return {
          objects: selected.map((key) => ({
            key,
            size: data.get(key).length,
            ...meta.get(key),
          })),
          truncated: keys.length > limit,
          cursor: selected.at(-1),
        };
      },
    };
  };
  const notices = [];
  return {
    sql,
    DB,
    EDGE_LIMITER: {
      async limit() {
        return { success: true };
      },
    },
    RAW: bucket(),
    REBUILT: bucket(),
    INTAKE_SECRET: "test-only-secret-with-at-least-thirty-two-characters",
    INTAKE_ENABLED: "true",
    NATIVE_ENABLED: "true",
    PROCESSING_ENABLED: "true",
    AI_SCREENING_ENABLED: "true",
    NOTIFICATIONS_ENABLED: "true",
    EMAIL_ENABLED: "true",
    JOBS: {
      sent: [],
      async send(value) {
        this.sent.push(value);
      },
    },
    AI: {
      async run() {
        return { response: JSON.stringify({ decision: "pass", reasons: [] }) };
      },
    },
    CONTACT_NOTIFY: {
      async send(message) {
        notices.push(message);
      },
    },
    notices,
    close: () => sql.close(),
  };
}
export const rawFileCount = (env) =>
  [...env.RAW.data.keys()].filter((key) => /^[a-f0-9-]{36}\//.test(key)).length;
