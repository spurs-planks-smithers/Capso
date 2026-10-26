function protectedResponse(response) {
  const out = new Response(response.body, response);
  out.headers.set(
    "Strict-Transport-Security",
    "max-age=31536000; includeSubDomains",
  );
  out.headers.set("X-Content-Type-Options", "nosniff");
  out.headers.set("Referrer-Policy", "no-referrer");
  out.headers.set("X-Frame-Options", "DENY");
  out.headers.set("X-Robots-Tag", "noindex, nofollow");
  out.headers.set(
    "Permissions-Policy",
    "camera=(), microphone=(), geolocation=()",
  );
  out.headers.set(
    "Content-Security-Policy",
    "default-src 'self'; script-src 'self' https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com; connect-src 'self' https://challenges.cloudflare.com; img-src 'self' data:; style-src 'self'; font-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'self'",
  );
  return out;
}

export async function secureFetch(request, handler) {
  const url = new URL(request.url);
  const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  if (url.protocol !== "https:" && !loopback) {
    if (["GET", "HEAD"].includes(request.method)) {
      url.protocol = "https:";
      return protectedResponse(
        new Response(null, { status: 308, headers: { Location: url.href } }),
      );
    }
    return protectedResponse(
      new Response(JSON.stringify({ error: "https_required" }), {
        status: 400,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      }),
    );
  }
  return protectedResponse(await handler());
}
