export const SCANNER_IMAGE_PREFIX =
  "registry.cloudflare.com/2afca1b8aab7ec4024bdb7cb2fec47c0/nextshot-feedback-scanner-scanner@sha256:";

export async function ensureScannerRuntime(managed, ctx) {
  const container = ctx.container;
  const image = container?.images?.scanner;
  if (
    typeof image !== "string" ||
    !image.startsWith(SCANNER_IMAGE_PREFIX) ||
    !/^[a-f0-9]{64}$/.test(image.slice(SCANNER_IMAGE_PREFIX.length))
  ) {
    throw new Error("scanner_image_unavailable");
  }
  if (typeof ctx.exports?.ContainerProxy !== "function") {
    throw new Error("scanner_proxy_unavailable");
  }
  await managed.applyOutboundInterceptionPromise;
  const info = await container.inspect();
  if (info && info.image !== "" && info.image !== image) {
    await managed.destroy();
  }
  // Replace SDK registration only after its initial interception completes.
  await container.interceptOutboundHttp(
    "signatures.nextshot.internal",
    ctx.exports.ContainerProxy({
      props: {
        enableInternet: false,
        containerId: ctx.id.toString(),
        className: managed.constructor.name,
      },
    }),
  );
  if (!container.running) {
    await container.start({
      image,
      instance: "standard-2",
      enableInternet: false,
    });
  }
}
