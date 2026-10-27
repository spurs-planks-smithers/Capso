import { metadata, commitPayload } from "./payload.js";
import { createRetention, requireRetention } from "./retention.js";
import PostalMime from "postal-mime";
import {
  LIMITS,
  enabled,
  fail,
  uploadBytes,
  digest,
  email as validEmail,
} from "./policy.js";
import { query, hmac, nowSeconds, admission, enqueue } from "./store.js";
async function htmlText(html) {
  const parts = [];
  const transformed = new HTMLRewriter()
    .on("*", {
      element(element) {
        for (const name of ["alt", "title", "href", "src"]) {
          const value = element.getAttribute(name);
          if (value) parts.push(value);
        }
      },
      text(chunk) {
        parts.push(chunk.text);
      },
    })
    .transform(new Response(html));
  await transformed.arrayBuffer();
  return parts.join(" ");
}
export async function inbound(message, env) {
  if (
    message.to.toLowerCase() !== "hi@nextshot.dev" ||
    !enabled(env, "EMAIL_ENABLED")
  ) {
    message.setReject("This address is not accepting messages.");
    return;
  }
  if (message.rawSize > LIMITS.rawEmailBytes) {
    message.setReject("Message exceeds the Nextshot size limit.");
    return;
  }
  const identity = await hmac(
    env.INTAKE_SECRET,
    `email:${message.from.toLowerCase()}`,
  );
  try {
    await admission(env, identity, true, "email");
  } catch {
    message.setReject("Nextshot intake is temporarily unavailable.");
    return;
  }
  let raw;
  try {
    raw = await uploadBytes(message.raw, LIMITS.rawEmailBytes);
  } catch {
    message.setReject("Message exceeds the Nextshot size limit.");
    return;
  }
  const id = crypto.randomUUID(),
    now = nowSeconds(),
    originalID = crypto.randomUUID(),
    originalKey = `${id}/${originalID}`;
  let parsed,
    text = "",
    contact = "",
    files = [],
    reasons = [];
  try {
    parsed = await PostalMime.parse(raw, {
      maxNestingDepth: 8,
      maxHeadersSize: 32768,
    });
    const plain = parsed.text || "",
      html = parsed.html || "";
    if (
      new TextEncoder().encode(plain).length +
        new TextEncoder().encode(html).length >
      LIMITS.textBytes
    )
      fail("email_text_limit");
    text = `Subject: ${parsed.subject || "(no subject)"}\n\n${plain}${html ? "\n\nHTML alternative as plain text:\n" + (await htmlText(html)) : ""}`;
    if (new TextEncoder().encode(text).length > LIMITS.textBytes)
      fail("email_text_limit");
    contact = validEmail(message.from) ? message.from : "";
    const attachments = parsed.attachments || [];
    let total = 0;
    if (attachments.length > LIMITS.files) fail("email_attachment_limit");
    for (const attachment of attachments) {
      if (
        !["image/png", "image/jpeg", "application/zip"].includes(
          attachment.mimeType,
        )
      )
        fail("email_attachment_type");
      const data = new Uint8Array(attachment.content);
      total += data.length;
      if (!data.length || total > LIMITS.fileBytes)
        fail("email_attachment_limit");
      files.push({ id: crypto.randomUUID(), type: attachment.mimeType, data });
    }
    if (files.some((f) => f.type === "application/zip") && files.length !== 1)
      fail("email_attachment_type");
    if (!plain && !html && !files.length) fail("email_empty");
  } catch (error) {
    reasons = [
      /^email_[a-z_]+$/.test(error?.code) ? error.code : "email_parse_failed",
    ];
    text = "";
    contact = "";
    files = [];
  }
  const status = reasons.length ? "held" : "received";
  await createRetention(env, id, now);
  await env.DB.batch([
    query(
      env,
      "INSERT INTO submissions(id,source,category,identity_hash,idempotency_key,fingerprint,token_hash,status,created_at,reservation_expires_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
      id,
      "email",
      "other",
      identity,
      id,
      await digest(raw),
      "",
      status,
      now,
      now,
      now + LIMITS.heldDays * 86400,
    ),
    query(
      env,
      "INSERT INTO files(id,submission_id,content_type,bytes,sha256,raw_key,role,status) VALUES(?,?,?,?,?,?,?,'pending')",
      originalID,
      id,
      "message/rfc822",
      raw.length,
      await digest(raw),
      originalKey,
      "email-original",
    ),
  ]);
  const record = await metadata(env, id);
  if (
    !(await commitPayload(
      env,
      record,
      {
        message: text,
        contact_email: contact,
        reason_codes: JSON.stringify(reasons),
      },
      { expected: { status } },
    ))
  )
    fail("payload_changed", 409);
  // Each object has a database record before its write so expiration can delete partial jobs.
  await requireRetention(env, record);
  await env.RAW.put(originalKey, raw, {
    httpMetadata: { contentType: "application/octet-stream" },
  });
  await requireRetention(env, record);
  await query(
    env,
    "UPDATE files SET status='uploaded' WHERE id=?",
    originalID,
  ).run();
  for (const file of files) {
    const key = `${id}/${file.id}`;
    await query(
      env,
      "INSERT INTO files(id,submission_id,content_type,bytes,sha256,raw_key,status) VALUES(?,?,?,?,?,?,'pending')",
      file.id,
      id,
      file.type,
      file.data.length,
      await digest(file.data),
      key,
    ).run();
    await requireRetention(env, record);
    await env.RAW.put(key, file.data, {
      httpMetadata: { contentType: "application/octet-stream" },
    });
    await requireRetention(env, record);
    await query(
      env,
      "UPDATE files SET status='uploaded' WHERE id=?",
      file.id,
    ).run();
  }
  if (status === "received") {
    try {
      await enqueue(env, id);
    } catch {
      /* The durable outbox preserves the received message. */
    }
  }
}
