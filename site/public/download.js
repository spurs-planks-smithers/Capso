// The page ships with one button that downloads the Mac app, so it works
// without JavaScript. Windows visitors get a disabled "Coming soon" button
// instead, plus a small Mac link, so no one downloads a DMG by accident.
(() => {
  const platform = navigator.userAgentData?.platform || navigator.userAgent || navigator.platform;
  if (!/windows|win32|win64/i.test(platform)) return;

  const option = document.querySelector(".download-option");
  const download = option?.querySelector(".download");
  if (!download) return;

  const soon = document.createElement("button");
  soon.className = `${download.className} soon`;
  soon.type = "button";
  soon.disabled = true;
  soon.setAttribute("aria-label", "Nextshot for Windows is coming soon");
  // A drawn window glyph, not the Windows logo (see docs/site.md).
  const ns = "http://www.w3.org/2000/svg";
  const icon = document.createElementNS(ns, "svg");
  icon.setAttribute("class", "platform-icon");
  icon.setAttribute("viewBox", "0 0 24 24");
  icon.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(ns, "path");
  path.setAttribute("fill-rule", "evenodd");
  path.setAttribute("d", "M4.5 3h15A1.5 1.5 0 0 1 21 4.5v15a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 19.5v-15A1.5 1.5 0 0 1 4.5 3zM4.8 4.8h6.3v6.3H4.8zM12.9 4.8h6.3v6.3h-6.3zM4.8 12.9h6.3v6.3H4.8zM12.9 12.9h6.3v6.3h-6.3z");
  icon.append(path);
  soon.append(icon, "Coming soon");

  const mac = document.createElement("a");
  mac.className = "platform-note mac-alternative";
  mac.href = download.getAttribute("href");
  mac.textContent = "Download for Mac";

  download.replaceWith(soon);
  option.append(mac);
})();
