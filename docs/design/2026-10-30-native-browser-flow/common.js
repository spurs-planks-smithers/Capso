// Shared parts for the native browser-flow mockups. Static HTML only.
const GLASS = `<svg viewBox="0 0 340 440" width="340" height="440"><path d="M20 92H320L292 420Q290 432 278 432H62Q50 432 48 420Z" fill="#e9f5f9" stroke="#c4d9de" stroke-width="5"/><path d="M26 142H314L292 420Q290 428 278 428H62Q50 428 48 420Z" fill="#fae38e"/><line x1="196" y1="8" x2="164" y2="310" stroke="#43cdbf" stroke-width="14" stroke-linecap="round"/><circle cx="296" cy="72" r="40" fill="#f2c718"/><circle cx="296" cy="72" r="30" fill="none" stroke="#fff" stroke-width="3"/><path d="M296 42V102M266 72H326M275 51L317 93M317 51L275 93" stroke="#fff" stroke-width="3"/></svg>`;
const LEMON = `<div class="lm"><div class="nav"><span>Menu</span><span>Order</span></div><h1>Lemonaid</h1><p class="tag">Fresh squeezed every day.</p><div class="price">$9 a cup</div><div class="buy">Buy</div><div class="foot">Open 9 to 5. Cash only.</div>${GLASS}</div>`;
const MARK = `<svg width="22" height="14" viewBox="0 0 22 14"><rect x="0" y="1" width="11" height="12" rx="3" fill="#8e8e93"/><path d="M9 1L19 7L9 13L11.5 7Z" fill="#111"/></svg>`;

function menubar(opts = {}) {
  const label = opts.label || 'Nshot Dev (3)';
  return `<div class="menubar"><b>Google Chrome</b><span>File</span><span>Edit</span><span>View</span><span>History</span><span>Bookmarks</span><span>Window</span><span>Help</span><span class="sp"></span><span class="nsh">${MARK}${label}${opts.dot === false ? '' : '<i class="dot"></i>'}</span><span>Fri 9:41 AM</span></div>`;
}
function chromeWindow(opts = {}) {
  const left = opts.left ?? 100, top = opts.top ?? 46;
  return `<div class="chrome" style="left:${left}px;top:${top}px;width:1240px;height:730px"><div class="c-top"><div class="lights"><i></i><i></i><i></i></div><div class="c-tab"><span class="fav"></span>Lemonaid - Menu</div></div><div class="c-bar"><span>&#8592;</span><span>&#8594;</span><span>&#8635;</span><div class="omni">lemonaid.example/menu</div><img src="nextshot-24.png" width="20" height="20" alt=""></div><div class="c-view">${LEMON}</div></div>`;
}
function hud(title, rows, o = {}) {
  const style = `left:${o.left ?? ''}px;top:${o.top ?? ''}px;${o.right != null ? `right:${o.right}px;` : ''}${o.bottom != null ? `bottom:${o.bottom}px;` : ''}`;
  return `<div class="hud" style="${style}${o.extra || ''}"><div class="t">${title}</div><div class="g">${rows.map(r => `<span class="k">${r[0]}</span><span class="a">${r[1]}</span>`).join('')}</div>${o.dot === false ? '' : '<i class="rd"></i>'}</div>`;
}
function noteBar(parts) {
  return `<div class="note"><span class="tag">Design note</span>${parts.map(p => `<span>${p}</span>`).join('')}</div>`;
}
function badge(n, x, y, sel) {
  return `<div class="badge${sel ? ' sel' : ''}" style="left:${x}px;top:${y}px">${n}</div>`;
}
