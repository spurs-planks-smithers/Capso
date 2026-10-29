import type {AssistInput,AssistResult} from './assistance.ts';
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
const originalSteps=new WeakMap<ActionEvent,ActionEvent>();
let assistRequest:string|undefined;
function invalidateAssistance():void{
  selectedRevision++;
  if(assistRequest){void chrome.runtime.sendMessage({type:'nextshot-assistance',action:'cancel',requestID:assistRequest});assistRequest=undefined;}
  document.getElementById('assistance-suggestions')?.replaceChildren();
}
const assistButton=document.createElement('button');assistButton.id='assist-steps';assistButton.textContent='Suggest relevant steps';
const assistSuggestions=document.createElement('div');assistSuggestions.id='assistance-suggestions';assistSuggestions.setAttribute('role','status');
$('add').after(assistButton,assistSuggestions);
void chrome.storage.local.get('assistanceMode').then(v=>{assistButton.hidden=!['apple','jev'].includes(String(v.assistanceMode));});
assistButton.onclick=async()=>{
  invalidateAssistance();const revision=selectedRevision,requestID=crypto.randomUUID();assistRequest=requestID;
  const candidates=steps.filter(step=>step.at>=start&&step.at<=end&&step.kind!=='excluded'&&originalSteps.has(step)).slice(0,32);
  if(!candidates.length){assistSuggestions.textContent='Add an observed step first.';return;}
  const selection:AssistInput={purpose:'steps',requestID,selectionVersion:revision,rollingID:state.id,issueAtMs:Math.round(issue-start),
    timeline:candidates.map((step,index)=>({id:`s${index}`,kind:originalSteps.get(step)!.kind,label:originalSteps.get(step)!.label,timeMs:Math.round(step.at-start)})),
    diagnostics:(state.diagnostics??[]).filter((d:any)=>d.at>=start&&d.at<=end).slice(0,8).map((d:any,index:number)=>({id:`d${index}`,kind:d.kind,summary:d.text})),candidates:[]};
  assistButton.disabled=true;assistSuggestions.textContent='Checking selected text. Your steps stay available.';
  try{const result:AssistResult=await chrome.runtime.sendMessage({type:'nextshot-assistance',action:'refine',selection});
    if(revision!==selectedRevision||!state)return;
    assistSuggestions.replaceChildren();
    if(!result.available||!result.ids.length){assistSuggestions.textContent='Local steps remain available.';return;}
    const label=document.createElement('p');label.textContent=`Suggested captured steps (${result.source==='apple'?'Apple':'Jev'}). Your list stays unchanged.`;assistSuggestions.append(label);
    const list=document.createElement('ul');for(const id of result.ids){const step=candidates[Number(id.slice(1))];if(!step||!/^s[0-9]+$/.test(id))continue;const row=document.createElement('li');row.textContent=step.label;list.append(row);}assistSuggestions.append(list);
  }catch{if(revision===selectedRevision)assistSuggestions.textContent='Local steps remain available.';}
  finally{assistButton.disabled=false;if(assistRequest===requestID)assistRequest=undefined;}
};
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
    check.checked = step.kind !== "excluded";
    input.type = "text";
    input.value = step.label;
    input.setAttribute(
      "aria-label",
      `Step at ${(step.at / 1000).toFixed(1)} seconds`,
    );
    input.oninput = () => {
      step.label = input.value;
      invalidateAssistance();
    };
    check.onchange = () => {
      step.kind = check.checked ? "click" : "excluded";
      invalidateAssistance();
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
    .map((s) => {const copy={...s};originalSteps.set(copy,{...s});return copy;});
  $<HTMLInputElement>("start").value = String(start / 1000);
  $<HTMLInputElement>("end").value = String(end / 1000);
  $("details").hidden = false;
  $("heading").textContent = "Review your selection";
  $("help").textContent =
    "The report includes the chosen failure frame and these observed setup steps.";
  $("status").textContent =
    "Selection ready. Continue, or adjust the steps and range.";
  invalidateAssistance();
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
    invalidateAssistance();
    renderSteps();
  };
$("add").onclick = () => {
  steps.push({ at: issue, kind: "click", label: "Describe the observed step" });
  invalidateAssistance();
  renderSteps();
};
$("cancel").onclick = async () => {
  invalidateAssistance();
  await call("cancel");
  window.close();
};
$("primary").onclick = async () => {
  const button = $<HTMLButtonElement>("primary");
  invalidateAssistance();
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
    invalidateAssistance();
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
  invalidateAssistance();
  if (url) URL.revokeObjectURL(url);
});
