import type { HistoryFrame } from "./core/history.ts";
/** Small low-color excerpts use GIF. Other excerpts use the existing video encoder. */
export async function compactGIF(
  frames: HistoryFrame[],
  start: number,
  end: number,
): Promise<Uint8Array | undefined> {
  if (frames.some((frame) => frame.at < start || frame.at > end)) return;
  frames = frames.filter((frame) => frame.at < end);
  if (frames[0]?.at !== start) return;
  if (!frames.length || frames.length > 6 || end - start > 6000 || end <= start)
    return;
  const width = Math.min(640, frames[0].width),
    height = Math.round((frames[0].height * width) / frames[0].width);
  const canvas = new OffscreenCanvas(width, height),
    ctx = canvas.getContext("2d")!,
    pixels: Uint8Array[] = [];
  for (const f of frames) {
    const image = await createImageBitmap(
      new Blob([new Uint8Array(f.bytes).buffer], { type: "image/jpeg" }),
    );
    ctx.fillStyle = "#252527";
    ctx.fillRect(0, 0, width, height);
    const scale = Math.min(width / image.width, height / image.height);
    ctx.drawImage(
      image,
      (width - image.width * scale) / 2,
      (height - image.height * scale) / 2,
      image.width * scale,
      image.height * scale,
    );
    image.close();
    const rgba = ctx.getImageData(0, 0, width, height).data,
      indexed = new Uint8Array(width * height),
      colors = new Set<number>();
    for (let i = 0; i < indexed.length; i++) {
      const c =
        (rgba[i * 4] & 224) |
        ((rgba[i * 4 + 1] & 224) >> 3) |
        (rgba[i * 4 + 2] >> 6);
      indexed[i] = c;
      colors.add(c);
    }
    if (colors.size > 32) return;
    pixels.push(indexed);
  }
  const out: number[] = [],
    word = (v: number) => out.push(v & 255, (v >> 8) & 255),
    ascii = (s: string) => out.push(...new TextEncoder().encode(s));
  ascii("GIF89a");
  word(width);
  word(height);
  out.push(0xf7, 0, 0);
  for (let c = 0; c < 256; c++)
    out.push(
      Math.round(((c >> 5) * 255) / 7),
      Math.round((((c >> 2) & 7) * 255) / 7),
      Math.round(((c & 3) * 255) / 3),
    );
  out.push(0x21, 0xff, 11);
  ascii("NETSCAPE2.0");
  out.push(3, 1, 0, 0, 0);
  // Reset before the dictionary needs ten-bit codes. Repeated colors use short dictionary references.
  for (let i = 0; i < pixels.length; i++) {
    const duration = Math.max(
      1,
      Math.floor(
        ((i + 1 < frames.length ? frames[i + 1].at : end) -
          Math.max(start, frames[i].at)) /
          10,
      ),
    );
    out.push(0x21, 0xf9, 4, 4);
    word(duration);
    out.push(0, 0, 0x2c);
    word(0);
    word(0);
    word(width);
    word(height);
    out.push(0, 8);
    const compressed: number[] = [];
    let bits = 0,
      count = 0;
    const code = (v: number) => {
      bits |= v << count;
      count += 9;
      while (count >= 8) {
        compressed.push(bits & 255);
        bits >>>= 8;
        count -= 8;
      }
    };
    code(256);
    let dictionary = new Map<number, number>(),
      next = 258,
      prefix = pixels[i][0];
    for (let j = 1; j < pixels[i].length; j++) {
      const value = pixels[i][j],
        key = prefix * 256 + value,
        known = dictionary.get(key);
      if (known !== undefined) {
        prefix = known;
        continue;
      }
      code(prefix);
      dictionary.set(key, next++);
      prefix = value;
      if (next >= 510) {
        code(256);
        dictionary = new Map();
        next = 258;
      }
    }
    code(prefix);
    code(257);
    if (count) compressed.push(bits & 255);
    for (let j = 0; j < compressed.length; j += 255) {
      const chunk = compressed.slice(j, j + 255);
      out.push(chunk.length, ...chunk);
    }
    out.push(0);
  }
  out.push(0x3b);
  return Uint8Array.from(out);
}
