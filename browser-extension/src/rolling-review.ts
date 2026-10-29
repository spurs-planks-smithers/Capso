import type { ActionEvent } from "./core/model.ts";
const $ = <T extends HTMLElement = HTMLElement>(id: string) =>
  document.getElementById(id)! as T;
const call = (action: string, extra: Record<string, unknown> = {}) =>
  chrome.runtime.sendMessage({ type: "nextshot-rolling", action, ...extra });
let state: any,
  issue = 0,
  start = 0,
  end = 0,
  steps: ActionEvent[] = [],
  url: string | undefined,
  previewRevision = 0,
  selectedRevision = 0;
const timeline = $<HTMLInputElement>("timeline");
function fail(e: unknown): void {
  $("status").textContent =
    e instanceof Error ? e.message : "History unavailable";
}
async function preview(): Promise<void> {
  const revision = ++previewRevision;
  const r = await call("preview", { at: Number(timeline.value) });
  if (revision !== previewRevision) return;
  if (r.error) throw Error(r.error);
  if (url) URL.revokeObjectURL(url);
  url = URL.createObjectURL(
    new Blob([new Uint8Array(r.bytes)], { type: "image/jpeg" }),
  );
  $<HTMLImageElement>("frame").src = url;
  $("time").textContent =
    `${(r.at / 1000).toFixed(1)} recorded seconds. Pauses are excluded.`;
}
function renderSteps(): void {
  $("steps").replaceChildren();
  for (const step of steps.filter((step) => step.at >= start && step.at <= end)) {
    const row = document.createElement("li"),
      check = document.createElement("input"),
      input = document.createElement("input");
    check.type = "checkbox";
    check.checked = true;
    input.type = "text";
    input.value = step.label;
    input.setAttribute(
      "aria-label",
      `Step at ${(step.at / 1000).toFixed(1)} seconds`,
    );
    input.oninput = () => {
      step.label = input.value;
      selectedRevision++;
    };
    check.onchange = () => {
      step.kind = check.checked ? "click" : "excluded";
      selectedRevision++;
    };
    row.append(check, input);
    $("steps").append(row);
  }
}
function mark(): void {
  issue = state.frames.reduce(
    (best: any, f: any) =>
      Math.abs(f.at - Number(timeline.value)) <
      Math.abs(best.at - Number(timeline.value))
        ? f
        : best,
    state.frames[0],
  ).at;
  const frames = state.frames as { at: number }[];
  const gaps = (state.diagnostics ?? []).filter(
    (d: any) =>
      d.kind === "gap" &&
      /^(Tracking paused|Tracking resumed|Review ended)/.test(d.text) &&
      d.at <= issue,
  );
  const segmentStart = Math.max(frames[0].at, gaps.at(-1)?.at ?? 0);
  start = Math.max(segmentStart, issue - 10000);
  end = Math.min(frames.at(-1)!.at, issue + 1000);
  steps = (state.actions as ActionEvent[])
    .filter((s) => s.at >= start && s.at <= issue)
    .slice(-12)
    .map((s) => ({ ...s }));
  $<HTMLInputElement>("start").value = String(start / 1000);
  $<HTMLInputElement>("end").value = String(end / 1000);
  $("details").hidden = false;
  $("heading").textContent = "Review your selection";
  $("help").textContent =
    "The report includes the chosen failure frame and these observed setup steps.";
  $("status").textContent =
    "Selection ready. Continue, or adjust the steps and range.";
  selectedRevision++;
  renderSteps();
}
timeline.oninput = () => {
  void preview().catch(fail);
};
$("mark").onclick = mark;
for (const id of ["start", "end"])
  $(id).oninput = () => {
    start = Number($<HTMLInputElement>("start").value) * 1000;
    end = Number($<HTMLInputElement>("end").value) * 1000;
    selectedRevision++;
    renderSteps();
  };
$("add").onclick = () => {
  steps.push({ at: issue, kind: "click", label: "Describe the observed step" });
  selectedRevision++;
  renderSteps();
};
$("cancel").onclick = async () => {
  await call("cancel");
  window.close();
};
$("primary").onclick = async () => {
  const button = $<HTMLButtonElement>("primary");
  button.disabled = true;
  try {
    const r = await call("select", {
      start,
      end,
      issue,
      steps: steps.filter((s) => s.kind !== "excluded"),
      identity: state.id,
      revision: state.revision,
    });
    if (r.error) throw Error(r.error);
    location.href = chrome.runtime.getURL(`review.html?draft=${r.id}`);
  } catch (e) {
    fail(e);
    button.disabled = false;
  }
};
// Refinements can inspect current selection. Revision checks preserve reviewer edits.
(globalThis as any).nextshotRollingSelection = {
  snapshot: () => ({
    identity: state?.id,
    ownerRevision: state?.revision,
    revision: selectedRevision,
    start,
    end,
    issue,
    steps: structuredClone(steps),
  }),
  apply: (revision: number, suggestions: ActionEvent[]) => {
    if (revision !== selectedRevision) return false;
    return suggestions.filter((s) => s.at >= start && s.at <= end);
  },
};
chrome.runtime.onMessage.addListener((m) => {
  if (m.type === "nextshot-rolling-invalidated") {
    if (url) URL.revokeObjectURL(url);
    url = undefined;
    state = undefined;
    steps = [];
    $<HTMLImageElement>("frame").removeAttribute("src");
    $("details").hidden = true;
    $("status").textContent = "Tracking stopped. Unsaved history was cleared.";
  }
});
async function load(): Promise<void> {
  const opened = performance.now();
  state = await call("status");
  if (!state.id || !state.reasons.includes("review") || !state.frames?.length)
    throw Error(
      "No captured history is available. Arm a tab and record some steps.",
    );
  timeline.min = String(state.frames[0].at);
  timeline.max = String(state.frames.at(-1).at);
  timeline.value = timeline.max;
  await preview();
  const candidates = state.frames.filter((f: any) =>
    f.alerts?.some((t: string) =>
      /\b(failed|failure|unable|cannot|could not)\b/i.test(t) && !/\b(no failures?|resolved|succeeded|success(?:ful(?:ly)?)?)\b/i.test(t),
    ),
  );
  const last = candidates.at(-1);
  if (last && performance.now() - opened <= 1000) {
    const suggestion = $<HTMLButtonElement>("suggestion");
    suggestion.hidden = false;
    suggestion.textContent = "Use captured failure alert";
    suggestion.onclick = () => {
      timeline.value = String(last.at);
      void preview().catch(fail);
      mark();
    };
  }
  $("status").textContent =
    "Choose the failure moment first. Tracking is paused.";
}
void load().catch(fail);
addEventListener("pagehide", () => {
  if (url) URL.revokeObjectURL(url);
});
