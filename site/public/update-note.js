// The Nextshot app opens this page as /#from=<version> when a person clicks
// "Get the latest version…". A browser never sends the part after the # to a
// server, so the version stays on this Mac. This script reads it here, compares
// it with the version the page already shows, and reveals one note.
//
// It sends nothing. site/test/update-note.test.mjs fails if a request, an
// image beacon, or HTML-writing code appears in this file.
(() => {
  "use strict";

  // Three plain numbers, no leading zeros, nothing after them. Anything else
  // (0.5.0-dev, 1.2.3.4, markup) is not a version and is never shown back.
  const SEMVER = /^(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})\.(0|[1-9]\d{0,8})$/;

  const parse = (text) => {
    const match = SEMVER.exec(typeof text === "string" ? text : "");
    return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : null;
  };

  // Negative when a is older than b, zero when equal, positive when newer.
  const compare = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];

  // What the page shows for a hash. Null means the hash is not #from=..., so
  // the page stays as it was. Otherwise the result holds the comparison line,
  // or null when the two versions cannot be compared or the visitor's copy is
  // not older. Only digits and dots of a parsed version reach the text.
  const describe = (hash, current) => {
    const prefix = "#from=";
    if (typeof hash !== "string" || !hash.startsWith(prefix)) return null;
    const have = parse(hash.slice(prefix.length));
    const latest = parse(current);
    if (!have || !latest) return { comparison: null };
    const order = compare(have, latest);
    if (order === 0) return { comparison: "You have the newest build." };
    if (order < 0) return { comparison: `You have ${have.join(".")}. Version ${latest.join(".")} is out.` };
    return { comparison: null };
  };

  // A test runs this file with no document and reads the functions.
  if (typeof document === "undefined") {
    globalThis.nextshotUpdateNote = { parse, compare, describe };
    return;
  }

  const note = document.getElementById("update-note");
  if (!note) return;
  const result = describe(window.location.hash, note.dataset.version);
  if (!result) return;
  const line = note.querySelector(".update-compare");
  if (line && result.comparison) {
    line.textContent = result.comparison;
    line.hidden = false;
  }
  note.hidden = false;
  document.body.classList.add("has-note");
})();
