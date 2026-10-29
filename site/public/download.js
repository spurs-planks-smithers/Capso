// Keep the Mac download usable without JavaScript. Windows gets a disabled
// button and an explicit Mac link, so its button never downloads a DMG.
(() => {
  const platform = navigator.userAgentData?.platform || navigator.userAgent || navigator.platform;
  if (!/windows|win32|win64/i.test(platform)) return;

  for (const option of document.querySelectorAll(".download-option")) {
    const download = option.querySelector(".download");
    const note = option.querySelector(".platform-note");
    const mac = document.createElement("a");
    mac.className = "platform-note mac-alternative";
    mac.href = download.getAttribute("href");
    mac.append(download.querySelector("svg").cloneNode(true), "Download for Mac");

    const soon = document.createElement("button");
    soon.className = `${download.className} soon`;
    soon.type = "button";
    soon.disabled = true;
    soon.append(note.querySelector("svg").cloneNode(true), "Windows coming soon");

    download.replaceWith(soon);
    note.replaceWith(mac);
  }
})();
