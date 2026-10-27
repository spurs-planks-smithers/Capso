import test from "node:test";
import assert from "node:assert/strict";
import { secureFetch } from "../src/http-security.js";
test("public insecure submissions fail before body parsing or dispatch", async () => {
  for (const method of ["POST", "PUT", "PATCH", "DELETE"]) {
    const request = new Request(
      "http://feedback.nextshot.dev/v1/reservations",
      { method, body: "private fixture" },
    );
    let called = false;
    const result = await secureFetch(request, async () => {
      called = true;
      await request.text();
      return new Response("unexpected");
    });
    assert.equal(result.status, 400);
    assert.deepEqual(await result.json(), { error: "https_required" });
    assert.equal(request.bodyUsed, false);
    assert.equal(called, false);
  }
});
test("public insecure GET and HEAD redirect to the same HTTPS URL", async () => {
  for (const method of ["GET", "HEAD"]) {
    let called = false;
    const result = await secureFetch(
      new Request("http://feedback.nextshot.dev/privacy.html?from=form", {
        method,
      }),
      async () => {
        called = true;
        return new Response("unexpected");
      },
    );
    assert.equal(result.status, 308);
    assert.equal(
      result.headers.get("Location"),
      "https://feedback.nextshot.dev/privacy.html?from=form",
    );
    assert.equal(called, false);
  }
});
test("HTTPS and exact loopback previews keep normal handling and all security headers", async () => {
  for (const host of [
    "https://feedback.nextshot.dev",
    "http://localhost:8876",
    "http://127.0.0.1:8876",
    "http://[::1]:8876",
  ]) {
    const request = new Request(host + "/v1/reservations", {
      method: "POST",
      body: "ordinary request",
    });
    let calls = 0;
    const result = await secureFetch(request, async () => {
      calls++;
      return new Response(await request.text(), {
        status: 202,
        headers: { "X-Existing": "kept" },
      });
    });
    assert.equal(calls, 1);
    assert.equal(result.status, 202);
    assert.equal(await result.text(), "ordinary request");
    assert.equal(result.headers.get("X-Existing"), "kept");
    assert.equal(
      result.headers.get("Strict-Transport-Security"),
      "max-age=31536000; includeSubDomains",
    );
    assert.equal(result.headers.get("X-Content-Type-Options"), "nosniff");
    assert.equal(result.headers.get("Referrer-Policy"), "same-origin");
    assert.equal(result.headers.get("X-Frame-Options"), "DENY");
    assert.equal(result.headers.get("X-Robots-Tag"), "noindex, nofollow");
    assert.equal(
      result.headers.get("Permissions-Policy"),
      "camera=(), microphone=(), geolocation=()",
    );
    assert.match(
      result.headers.get("Content-Security-Policy"),
      /object-src 'none'; frame-ancestors 'none'; form-action 'self'/,
    );
  }
  for (const host of [
    "http://localhost.evil.invalid",
    "http://127.0.0.2",
    "http://[::2]",
  ]) {
    const result = await secureFetch(
      new Request(host + "/submit", { method: "POST", body: "private" }),
      async () => new Response("unexpected"),
    );
    assert.equal(result.status, 400);
  }
});
