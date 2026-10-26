import { enabled, safeText } from "./policy.js";
import { query } from "./store.js";
export async function notifyScreened(env, row) {
  if (!enabled(env, "NOTIFICATIONS_ENABLED") || !env.CONTACT_NOTIFY) return;
  const lease = await query(
    env,
    "UPDATE submissions SET notified=2 WHERE id=? AND status='screened' AND notified=0 RETURNING id",
    row.id,
  ).first();
  if (!lease) return;
  const text = [
    `Nextshot feedback ${row.id}`,
    `Category: ${row.category}`,
    "Screening completed without a detected issue. This content remains untrusted.",
    `Contact address (unverified): ${row.contact_email ? safeText(row.contact_email) : "not supplied"}`,
    "",
    safeText(row.screened_text),
    "",
    `Review files and issue draft: https://feedback.nextshot.dev/review/${row.id}`,
  ].join("\n");
  try {
    await env.CONTACT_NOTIFY.send({
      from: "hi@nextshot.dev",
      to: "drewschulz1@gmail.com",
      subject: `Nextshot feedback ${row.id}`,
      text,
      ...(row.contact_email ? { replyTo: row.contact_email } : {}),
    });
    await query(
      env,
      "UPDATE submissions SET notified=1 WHERE id=?",
      row.id,
    ).run();
  } catch {
    await query(
      env,
      "UPDATE submissions SET notified=0 WHERE id=?",
      row.id,
    ).run();
  }
}
export async function notifyHeld(env) {
  if (!enabled(env, "NOTIFICATIONS_ENABLED") || !env.CONTACT_NOTIFY) return;
  const rows = (
    await query(
      env,
      "SELECT id,status,reason_codes FROM submissions WHERE status IN ('held','rejected') AND notified=0 LIMIT 100",
    ).all()
  ).results;
  if (!rows.length) return;
  const claims = [];
  for (const row of rows) {
    const claim = await query(
      env,
      "UPDATE submissions SET notified=2 WHERE id=? AND notified=0 RETURNING id",
      row.id,
    ).first();
    if (claim) claims.push(row);
  }
  if (!claims.length) return;
  const counts = {};
  for (const row of claims) {
    let codes;
    try {
      codes = JSON.parse(row.reason_codes);
    } catch {
      codes = ["screening_incomplete"];
    }
    for (const code of codes)
      counts[/^[-a-z0-9_]{1,64}$/.test(code) ? code : "screening_incomplete"] =
        (counts[code] || 0) + 1;
  }
  try {
    await env.CONTACT_NOTIFY.send({
      from: "hi@nextshot.dev",
      to: "drewschulz1@gmail.com",
      subject: `Nextshot feedback: ${claims.length} submissions held`,
      text: `${claims.length} submissions need review. No submitted content is included.\n\n${Object.entries(
        counts,
      )
        .map(([code, count]) => `${code}: ${count}`)
        .join("\n")}\n\nReview: https://feedback.nextshot.dev/review`,
    });
    for (const row of claims)
      await query(
        env,
        "UPDATE submissions SET notified=1 WHERE id=?",
        row.id,
      ).run();
  } catch {
    for (const row of claims)
      await query(
        env,
        "UPDATE submissions SET notified=0 WHERE id=?",
        row.id,
      ).run();
  }
}
