import {beginFrameContext,type FrameContext} from './frame-context.ts';
import { newCapture, saveDraft, discardDraft } from "./core/index.ts";
import type { ActionEvent, Asset } from "./core/model.ts";
export type RollingPause =
  "focus" | "review" | "navigation" | "manual" | "selection" | "snapshot";
interface Owner {
  id: string;
  revision: number;
  tabId: number;
  windowId: number;
  origin: string;
  clock: number;
  lastTick: number;
  reasons: RollingPause[];
  reviewTab?: number;
  draftId?: string;
  stopped: boolean;
  pauseWallStarted?: number;
}
let owner: Owner | undefined,
  timer: ReturnType<typeof setInterval> | undefined,
  busy = false,
  epoch = 0;
const call = (type: string, values: Record<string, unknown> = {}) =>
  chrome.runtime.sendMessage({ target: "recorder", type, ...values });
async function persist(): Promise<void> {
  if (owner) await chrome.storage.session.set({ rollingOwner: owner });
  else await chrome.storage.session.remove("rollingOwner");
  await chrome.action.setBadgeText({
    text: owner ? (owner.reasons.length ? "II" : "ARM") : "",
  });
  await chrome.action.setBadgeBackgroundColor({
    color: owner?.reasons.length ? "#815700" : "#12674b",
  });
}
function tick(): number {
  if (!owner) return 0;
  const now = Date.now();
  if (!owner.reasons.length)
    owner.clock += Math.max(0, Math.min(2000, now - owner.lastTick));
  owner.lastTick = now;
  return owner.clock;
}
function startTimer(): void {
  if (!timer)
    timer = setInterval(() => {
      void sample();
    }, 1000);
}
const recovery = (async () => {
  const saved = (await chrome.storage.session.get("rollingOwner"))
    .rollingOwner as Owner | undefined;
  if (!saved) return;
  try {
    if (!(await chrome.offscreen.hasDocument())) throw Error();
    await chrome.tabs.get(saved.tabId);
    owner = saved;
    owner.lastTick = Date.now();
    if (!owner.reasons.includes("snapshot")) owner.reasons.push("snapshot");
    await persist();
    startTimer();
    const tab = await chrome.tabs.get(saved.tabId);
    if (new URL(tab.url ?? "").origin === saved.origin) {
      await observe(owner);
      owner.reasons = owner.reasons.filter((r) => r !== "snapshot");
      await persist();
    } else if (!owner.reasons.includes("navigation")) {
      owner.reasons.push("navigation");
      await persist();
    }
  } catch {
    owner = undefined;
    if (timer) clearInterval(timer);
    timer = undefined;
    await persist();
    if (saved.draftId) await discardDraft(saved.draftId);
    try { if (await chrome.offscreen.hasDocument()) await chrome.offscreen.closeDocument(); } catch {}
  }
})();
export async function pauseForSelection(): Promise<void> {
  await rollingPause("selection", true);
  while (busy) await new Promise((r) => setTimeout(r, 10));
}
export async function rollingStatus(): Promise<any> {
  await recovery;
  return owner
    ? { ...owner, ...(await call("status")) }
    : { stopped: true, frames: [] };
}
export async function rollingPause(
  reason: RollingPause,
  paused: boolean,
): Promise<void> {
  await recovery;
  const current = owner;
  if (!current) return;
  tick();
  const wasPaused = current.reasons.length > 0,
    had = current.reasons.includes(reason);
  current.reasons = current.reasons.filter((r) => r !== reason);
  if (paused) current.reasons.push(reason);
  current.lastTick = Date.now();
  if (!wasPaused && current.reasons.length)
    current.pauseWallStarted = Date.now();
  const resumed = wasPaused && !current.reasons.length;
  const gap = resumed
    ? `Tracking resumed after ${Math.max(0, (Date.now() - (current.pauseWallStarted ?? Date.now())) / 1000).toFixed(1)} seconds paused. New continuous segment.`
    : undefined;
  if (resumed) delete current.pauseWallStarted;
  if (had !== paused) {
    current.revision++;
    await persist();
    if (owner !== current) return;
    if (paused)
      await call("event", {
        at: current.clock,
        kind: "gap",
        label: `Tracking paused: ${reason}. Recorded-time clock excludes this gap.`,
      });
  }
  if (gap && owner === current)
    await call("event", { at: current.clock, kind: "gap", label: gap });
}
async function observe(current: Owner): Promise<void> {
  await chrome.scripting.executeScript({
    target: { tabId: current.tabId },
    files: ["content.js"],
  });
  await chrome.tabs.sendMessage(current.tabId, {
    type: "nextshot-record-observe",
    rolling: true,
  });
}
export async function armRolling(tabId: number): Promise<void> {
  await recovery;
  const attempt = ++epoch;
  if (!(await chrome.storage.local.get("rollingEnabled")).rollingEnabled)
    throw Error("Enable the Rolling Round trial first.");
  if ((await chrome.storage.session.get("recordingOwner")).recordingOwner)
    throw Error("Discard the ordinary recording first.");
  const tab = await chrome.tabs.get(tabId);
  if (!tab.url || !/^https?:/.test(tab.url))
    throw Error("Choose a website tab.");
  const origin = new URL(tab.url).origin;
  if (
    !(await chrome.permissions.contains({
      permissions: ["offscreen"],
      origins: [origin + "/*"],
    }))
  )
    throw Error("Approve site access first.");
  if (epoch !== attempt) throw Error("Arming was canceled.");
  if (owner) {
    await stopRolling();
    if (attempt + 1 !== epoch) throw Error("Arming was canceled.");
  }
  const armEpoch = epoch;
  if (!(await chrome.offscreen.hasDocument()))
    await chrome.offscreen.createDocument({
      url: "offscreen.html",
      reasons: [chrome.offscreen.Reason.BLOBS],
      justification:
        "Hold the explicitly armed tab’s bounded masked history in memory.",
    });
  if (armEpoch !== epoch) {
    if (!owner && (await chrome.offscreen.hasDocument()))
      await chrome.offscreen.closeDocument();
    throw Error("Arming was canceled.");
  }
  await call("configure", { rolling: true });
  if (armEpoch !== epoch) throw Error("Arming was canceled.");
  owner = {
    id: crypto.randomUUID(),
    revision: 0,
    tabId,
    windowId: tab.windowId,
    origin,
    clock: 0,
    lastTick: Date.now(),
    reasons: [],
    stopped: false,
  };
  await persist();
  await call("event", {
    at: 0,
    kind: "coverage",
    label:
      "Silent sampled evidence at most once per second. Fields and embedded frames are covered. No typed values. Console, request methods/status, failed requests, and embedded-frame activity are unavailable.",
  });
  try {
    await observe(owner);
    startTimer();
    await sample();
  } catch (e) {
    await stopRolling();
    throw e;
  }
}
export async function stopRolling(): Promise<void> {
  await recovery;
  epoch++;
  const pending = (await chrome.storage.session.get("pendingIntent"))
    .pendingIntent as { kind?: string } | undefined;
  if (pending?.kind === "rolling")
    await chrome.storage.session.remove("pendingIntent");
  const old = owner;
  if (!old) return;
  old.stopped = true;
  owner = undefined;
  void chrome.runtime
    .sendMessage({ type: "nextshot-rolling-invalidated", draftId: old.draftId })
    .catch(() => {});
  if (timer) clearInterval(timer);
  timer = undefined;
  await persist();
  await chrome.tabs
    .sendMessage(old.tabId, { type: "nextshot-record-cleanup" })
    .catch(() => {});
  if (old.draftId) await discardDraft(old.draftId);
  while (busy) await new Promise((r) => setTimeout(r, 10));
  try {
    if (await chrome.offscreen.hasDocument())
      await chrome.offscreen.closeDocument();
  } catch {}
}
async function focus(): Promise<void> {
  if (!owner) return;
  const current = owner;
  const window = await chrome.windows.get(current.windowId);
  const active = (
    await chrome.tabs.query({ active: true, windowId: current.windowId })
  )[0];
  if (owner !== current) return;
  await rollingPause("focus", !window.focused || active?.id !== current.tabId);
}
async function sample(): Promise<void> {
  await recovery;
  if (!owner || busy) return;
  await focus();
  if (!owner || owner.reasons.length) return;
  busy = true;
  const current = owner;
  const at = tick();
  let frames:FrameContext|undefined;
  try {
    const proof = await chrome.tabs.sendMessage(current.tabId, {
      type: "nextshot-record-frame",
    });
    if (!proof?.proofId) throw Error("No proof");
    frames=await beginFrameContext(current.tabId);
    const image = await chrome.tabs.captureVisibleTab(current.windowId, {
      format: "png",
    });
    const confirmed = await chrome.tabs.sendMessage(current.tabId, {
      type: "nextshot-confirm-capture",
      proofId: proof.proofId,
    });
    const tab = await chrome.tabs.get(current.tabId),
      active = (
        await chrome.tabs.query({ active: true, windowId: current.windowId })
      )[0],
      window = await chrome.windows.get(current.windowId);
    if (
      active?.id !== current.tabId ||
      !window.focused ||
      current !== owner ||
      current.stopped ||
      current.reasons.length ||
      !confirmed?.ok ||
      frames&&!await frames.confirm() ||
      new URL(tab.url ?? "").origin !== current.origin
    )
      throw Error("Snapshot changed");
    await call("frame", { image, proof:frames?{...proof,elements:frames.elements,privateRects:frames.privateRects}:proof, at });
  } catch {
    if (current === owner)
      await call("event", {
        at,
        kind: "gap",
        label:
          "Frame unavailable: capture-time privacy proof could not be verified.",
      }).catch(() => {});
  } finally {
    await frames?.release();
    await chrome.tabs
      .sendMessage(current.tabId, { type: "nextshot-record-release" })
      .catch(() => {});
    busy = false;
    if (current === owner) await persist();
  }
}
export async function rollingEvent(
  tabId: number,
  kind: string,
  label: string,
): Promise<void> {
  await recovery;
  if (
    !owner ||
    owner.tabId !== tabId ||
    owner.reasons.length ||
    !["click", "error", "request"].includes(kind)
  )
    return;
  await call("event", { at: tick(), kind, label });
}
export async function openRolling(): Promise<void> {
  await recovery;
  if (!owner) throw Error("Arm a tab first.");
  if (owner.reasons.includes("review")) {
    if (owner.reviewTab)
      await chrome.tabs.update(owner.reviewTab, { active: true });
    return;
  }
  await rollingPause("review", true);
  while (busy) await new Promise((r) => setTimeout(r, 10));
  const tab = await chrome.tabs.create({
    url: chrome.runtime.getURL("rolling.html"),
  });
  if (owner) {
    owner.reviewTab = tab.id;
    owner.revision++;
    await persist();
  }
}
export async function finishRollingReview(): Promise<void> {
  await recovery;
  if (!owner) return;
  const current = owner;
  if (current.draftId) await discardDraft(current.draftId);
  if (owner !== current) return;
  delete current.draftId;
  delete current.reviewTab;
  await rollingPause("review", false);
  await call("event", {
    at: tick(),
    kind: "gap",
    label:
      "Review ended. Tracking resumes in a new continuous segment when all pause reasons clear.",
  });
  await focus();
}
export async function rollingPreview(at: number): Promise<any> {
  await recovery;
  if (!owner?.reasons.includes("review"))
    throw Error("Open Rolling Round first.");
  return call("preview", { at });
}
/** Selected evidence hooks carry owner identity and revision. Late assist results cannot revive discarded owners. */
export async function rollingSelection(
  start: number,
  end: number,
  issue: number,
  steps: ActionEvent[],
  identity: string,
  revision: number,
): Promise<string> {
  await recovery;
  const current = owner;
  if (
    !current ||
    current.id !== identity ||
    current.revision !== revision ||
    !current.reasons.includes("review")
  )
    throw Error("This review is no longer current.");
  if (!Number.isFinite(issue) || issue < start || issue > end)
    throw Error("Choose an issue inside the selected range.");
  const selected = await call("select", { start, end, issue, rolling: true });
  if (selected.error) throw Error(selected.error);
  if (owner !== current || current.stopped || current.revision !== revision)
    throw Error("This review was discarded.");
  const capture = newCapture({
    title: selected.frame.title || "Rolling Round",
    url: selected.frame.url,
    width: selected.frame.width,
    height: selected.frame.height,
  });
  capture.kind = "rolling";
  capture.createdAt = selected.frame.capturedAt ?? capture.createdAt;
  capture.elements = selected.frame.elements ?? [];
  capture.actions = selected.actions;
  capture.diagnostics = [{at:start,kind:'coverage',text:'Silent sampled frames, at most once per second. No audio or typed values. Fields and embedded frames are covered. Console, complete request methods/status/failures, and embedded-frame activity are unavailable.'},...selected.diagnostics.slice(-999)];
  capture.clip = {
    start,
    end,
    issue,
    steps: steps
      .filter((s) => Number.isFinite(s.at) && s.at >= start && s.at <= end)
      .slice(0, 100),
  };
  const bytes = new Uint8Array(selected.frame.bytes),
    assets: Asset[] = [
      { name: capture.imageFile, mime: "image/jpeg", bytes },
      { name: capture.cleanImageFile, mime: "image/jpeg", bytes },
    ];
  capture.keyFrames = (selected.keyFrames ?? []).map((f: any, i: number) => {
    const file = `${capture.id}-key-${i + 1}.jpg`;
    assets.push({
      name: file,
      mime: "image/jpeg",
      bytes: new Uint8Array(f.bytes),
    });
    return { at: f.at, file, width: f.width, height: f.height };
  });
  if (selected.media) {
    capture.clip.mediaFile = `${capture.id}-selected.${selected.mediaMime === "image/gif" ? "gif" : "webm"}`;
    capture.clip.mime = selected.mediaMime;
    assets.push({
      name: capture.clip.mediaFile,
      mime: selected.mediaMime,
      bytes: new Uint8Array(selected.media),
    });
  }
  await saveDraft({ capture, assets });
  if (owner !== current || current.stopped) {
    await discardDraft(capture.id);
    throw Error("This review was discarded.");
  }
  current.draftId = capture.id;
  await persist();
  return capture.id;
}
chrome.tabs.onActivated.addListener(() => {
  void recovery.then(focus);
});
chrome.windows.onFocusChanged.addListener(() => {
  void recovery.then(focus);
});
chrome.tabs.onRemoved.addListener((id) => {
  void recovery.then(async () => {
    if (owner?.tabId === id) await stopRolling();
    else if (owner?.reviewTab === id) await finishRollingReview();
  });
});
chrome.tabs.onUpdated.addListener((id, change, tab) => {
  void recovery.then(async () => {
    if (owner?.tabId !== id) return;
    const current = owner;
    if (change.status === "loading") {
      await rollingPause("snapshot", true);
      if (tab.url && new URL(tab.url).origin !== current.origin)
        await rollingPause("navigation", true);
    }
    if (change.status === "complete") {
      if (new URL(tab.url ?? "").origin !== current.origin) {
        await rollingPause("navigation", true);
        return;
      }
      try {
        await observe(current);
        if (owner !== current) return;
        await rollingPause("snapshot", false);
        await focus();
      } catch {
        await rollingPause("snapshot", true);
      }
    }
  });
});
chrome.permissions.onRemoved.addListener(() => {
  void recovery.then(() => stopRolling());
});
chrome.runtime.onStartup.addListener(() => {
  void recovery.then(() => stopRolling());
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (
    area === "local" &&
    "rollingEnabled" in changes &&
    !changes.rollingEnabled.newValue
  )
    void stopRolling();
});
