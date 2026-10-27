import { DurableObject, WorkerEntrypoint } from "cloudflare:workers";
import { SCANNER_IDLE_MS } from "./scanner-runtime.js";
import { scannerFetch, signatureProxy } from "./scanner-http.js";
import { verifyScannerIsolation } from "./scanner-diagnostic.js";
export { scan } from "./scanner-client.js";

export class Scanner extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      // Remove the old SDK alarm. Native inactivity control owns shutdown.
      await ctx.storage.deleteAlarm();
      if (ctx.container?.running)
        await ctx.container.setInactivityTimeout(SCANNER_IDLE_MS);
    });
  }
  async verifyIsolation() {
    return verifyScannerIsolation(this, this.ctx, this.env, arguments.length);
  }
  async fetch(request) {
    return scannerFetch(this, this.ctx, request);
  }
}
export class ContainerProxy extends WorkerEntrypoint {
  async fetch(request) {
    return signatureProxy(request, this.env);
  }
}
