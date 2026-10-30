/** Text-only protocol mirror of site/jev/src/policy.js. Keep both validators in step. */
export const JEV_ORIGIN = 'https://jev.nextshot.dev';
export const JEV_CLIENT = 'nextshot-chrome-dev';
export const JEV_REDIRECT = 'https://ghmidcmcjigfckaiopacgpfaffofgjel.chromiumapp.org/jev';
export interface JevPolicy { jevEnabled: boolean; jevConsentPageData: boolean; jevConsentReviewerText: boolean }
export interface JevSelection {
  purpose: 'steps' | 'elements'; requestID: string; selectionVersion: string;
  timeline: {id: string; kind: string; label: string; timeMs: number}[];
  diagnostics: {id: string; kind: string; summary: string}[];
  candidates: {id: string; role: string; label: string}[];
  reviewerNote?: string; issueTimeMs?: number;
}
export type JevResult = {available: true; candidates: {id: string; confidence: number}[]} | {available: false; fallback: 'local'; reason: string};
interface Session { access: string; refresh: string; expiresAt: number }
export interface JevDependencies {
  fetch: typeof fetch;
  identity: Pick<typeof chrome.identity, 'launchWebAuthFlow' | 'getRedirectURL'>;
  storage: Pick<typeof chrome.storage.local, 'get' | 'set' | 'remove' | 'setAccessLevel'>;
  now: () => number;
}
const TOKEN = /^[A-Za-z0-9_-]{43}$/;
const ID = /^[A-Za-z0-9_-]{1,64}$/;
const SESSION_KEY = 'jevSessionV1';
const fallback = (reason: string): JevResult => ({available: false, fallback: 'local', reason});
function record(value: unknown, fields: readonly string[]): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(k => !fields.includes(k))) throw Error('invalid');
  return value as Record<string, unknown>;
}
function text(value: unknown, max = 512): string {
  if (typeof value !== 'string' || !value.length || value.length > max || /[\u0000-\u001f]/.test(value)
    || /https?:|www\.|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|Bearer\s|(?:sk|pk|api)[_-][A-Za-z0-9]{16,}/i.test(value)) throw Error('invalid');
  return value;
}
function identifier(value: unknown): string { const result = text(value, 64); if (!ID.test(result)) throw Error('invalid'); return result; }
function encoded(bytes: Uint8Array): string { return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', ''); }
function random(): string { return encoded(crypto.getRandomValues(new Uint8Array(32))); }
function payload(selection: JevSelection, policy: JevPolicy): string {
  const v = record(selection, ['purpose', 'requestID', 'selectionVersion', 'timeline', 'diagnostics', 'candidates', 'reviewerNote', 'issueTimeMs']);
  if (v.purpose !== 'steps' && v.purpose !== 'elements') throw Error('invalid');
  identifier(v.requestID); identifier(v.selectionVersion);
  if(v.issueTimeMs!==undefined&&(!Number.isInteger(v.issueTimeMs)||(v.issueTimeMs as number)<0||(v.issueTimeMs as number)>60000))throw Error('invalid');
  for (const [field, max, fields] of [
    ['timeline', 32, ['id', 'kind', 'label', 'timeMs']], ['diagnostics', 8, ['id', 'kind', 'summary']], ['candidates', 16, ['id', 'role', 'label']],
  ] as const) {
    const rows = v[field]; if (!Array.isArray(rows) || rows.length > max) throw Error('invalid');
    const ids = new Set<string>();
    for (const value of rows) {
      const row = record(value, fields);
      if (fields.some(k => !Object.hasOwn(row, k))) throw Error('invalid');
      const id = identifier(row.id); if (ids.has(id)) throw Error('invalid'); ids.add(id);
      for (const [k, item] of Object.entries(row)) {
        if (k === 'timeMs') { if (!Number.isInteger(item) || (item as number) < 0 || (item as number) > 60000) throw Error('invalid'); }
        else text(item);
      }
    }
  }
  if (!(selection.purpose === 'steps' ? selection.timeline : selection.candidates).length) throw Error('invalid');
  // Serialize before yielding so caller mutations cannot change the request or its reply binding.
  const result = JSON.stringify({version: 1, purpose: selection.purpose, requestID: selection.requestID, selectionVersion: selection.selectionVersion,
    consent: {pageData: true, reviewerText: policy.jevConsentReviewerText === true},
    ...(selection.issueTimeMs!==undefined?{issueTimeMs:selection.issueTimeMs}:{}),
    timeline: selection.timeline.map(({id, kind, label, timeMs}) => ({id, kind, label, timeMs})),
    diagnostics: selection.diagnostics.map(({id, kind, summary}) => ({id, kind, summary})),
    candidates: selection.candidates.map(({id, role, label}) => ({id, role, label})),
    ...(policy.jevConsentReviewerText === true && selection.reviewerNote !== undefined ? {reviewerNote: text(selection.reviewerNote, 1024)} : {})});
  if (new TextEncoder().encode(result).length > 24576) throw Error('invalid');
  return result;
}

/** Instantiate once in the trusted service worker. Never return tokens to extension pages or content scripts. */
export function createJevClient(dependencies?: JevDependencies) {
  const d = dependencies ?? {fetch: globalThis.fetch.bind(globalThis), identity: {getRedirectURL:(path?:string)=>chrome.identity.getRedirectURL(path),launchWebAuthFlow:(options:chrome.identity.WebAuthFlowDetails)=>chrome.identity.launchWebAuthFlow(options)}, storage: chrome.storage.local, now: Date.now};
  let epoch = 0;
  let refreshing: Promise<Session | null> | undefined;
  let signingIn = false;
  let signingOut: Promise<void> | undefined;
  const ready = d.storage.setAccessLevel({accessLevel: 'TRUSTED_CONTEXTS'});
  async function read(): Promise<Session | null> {
    await ready;
    const v = (await d.storage.get(SESSION_KEY))[SESSION_KEY] as Session | undefined;
    return v && TOKEN.test(v.access) && TOKEN.test(v.refresh) && Number.isFinite(v.expiresAt) ? v : null;
  }
  async function json(path: string, init: RequestInit, signal?: AbortSignal, timeout = 4000): Promise<{status: number; body: unknown}> {
    const controller = new AbortController(), cancel = () => controller.abort();
    const timer = setTimeout(cancel, timeout);
    signal?.addEventListener('abort', cancel, {once: true}); if (signal?.aborted) cancel();
    try {
      const response = await d.fetch(JEV_ORIGIN + path, {...init, signal: controller.signal, redirect: 'error', credentials: 'omit', cache: 'no-store', referrerPolicy: 'no-referrer'});
      const reader = response.body?.getReader(); if (!reader) throw Error('invalid');
      const chunks: Uint8Array[] = []; let size = 0;
      try {while (true) { const next = await reader.read(); if (next.done) break; size += next.value.length; if (size > 24576) throw Error('invalid'); chunks.push(next.value); }}
      finally {await reader.cancel().catch(() => {});}
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) {bytes.set(chunk, offset); offset += chunk.length;}
      if (controller.signal.aborted) throw Error('canceled');
      return {status: response.status, body: JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes))};
    } finally {clearTimeout(timer); signal?.removeEventListener('abort', cancel);}
  }
  async function exchange(body: object, generation: number): Promise<Session | null> {
    const response = await json('/auth/token', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
    if (generation !== epoch) return null;
    if (response.status !== 200) {await d.storage.remove(SESSION_KEY); return null;}
    const v = record(response.body, ['access_token', 'refresh_token', 'token_type', 'expires_in', 'scope', 'issuer', 'audience']);
    if (typeof v.access_token !== 'string' || !TOKEN.test(v.access_token) || typeof v.refresh_token !== 'string' || !TOKEN.test(v.refresh_token)
      || v.token_type !== 'Bearer' || v.scope !== 'jev:refine' || v.issuer !== JEV_ORIGIN || v.audience !== JEV_CLIENT || v.expires_in !== 3600) throw Error('invalid');
    const session = {access: v.access_token, refresh: v.refresh_token, expiresAt: d.now() + 3600000};
    await d.storage.set({[SESSION_KEY]: session});
    if (generation !== epoch) {await d.storage.remove(SESSION_KEY); return null;}
    return session;
  }
  async function session(): Promise<Session | null> {
    if (refreshing) return refreshing;
    const existing = await read();
    if (refreshing) return refreshing;
    if (!existing || existing.expiresAt > d.now() + 30000) return existing;
    if (refreshing) return refreshing;
    const generation = epoch;
    refreshing = (async () => {
      // Clear single-use refresh credentials before delivery. Uncertain delivery must never replay them.
      await d.storage.remove(SESSION_KEY);
      try {return await exchange({grant_type: 'refresh_token', client_id: JEV_CLIENT, refresh_token: existing.refresh}, generation);}
      catch {return null;}
    })();
    try {return await refreshing;} finally {refreshing = undefined;}
  }
  return {
    /** Explicit Sign In only. Authentication never enables Jev or grants consent. */
    async signIn(): Promise<{signedIn: boolean}> {
      if (signingIn || signingOut || refreshing) return {signedIn: false};
      signingIn = true; const generation = ++epoch;
      try {
        await ready;
        if (d.identity.getRedirectURL('jev') !== JEV_REDIRECT) return {signedIn: false};
        const verifier = random(), state = random();
        const challenge = encoded(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
        const url = new URL(JEV_ORIGIN + '/auth/authorize');
        url.search = new URLSearchParams({client_id: JEV_CLIENT, redirect_uri: JEV_REDIRECT, response_type: 'code', scope: 'jev:refine', code_challenge_method: 'S256', code_challenge: challenge, state}).toString();
        const redirect = await d.identity.launchWebAuthFlow({url: url.href, interactive: true});
        if (!redirect || generation !== epoch) return {signedIn: false};
        const result = new URL(redirect);
        if (result.origin + result.pathname !== JEV_REDIRECT || result.hash || result.searchParams.get('state') !== state || result.searchParams.get('iss') !== JEV_ORIGIN
          || [...result.searchParams.keys()].some(k => !['code', 'state', 'iss'].includes(k)) || ['code', 'state', 'iss'].some(k => result.searchParams.getAll(k).length !== 1)
          || !TOKEN.test(result.searchParams.get('code') ?? '')) return {signedIn: false};
        return {signedIn: !!await exchange({grant_type: 'authorization_code', client_id: JEV_CLIENT, redirect_uri: JEV_REDIRECT, code: result.searchParams.get('code'), code_verifier: verifier}, generation)};
      } catch {return {signedIn: false};} finally {signingIn = false;}
    },
    async signOut(): Promise<void> {
      if (signingOut) return signingOut;
      signingOut = (async () => {
        try {
          const existing = await session();
          ++epoch;
          await d.storage.remove(SESSION_KEY);
          if (existing) await json('/auth/revoke', {method: 'POST', headers: {Authorization: `Bearer ${existing.access}`}}).catch(() => {});
        } finally {++epoch; await d.storage.remove(SESSION_KEY);}
      })();
      try {await signingOut;} finally {signingOut = undefined;}
    },
    /** Local status only. No refresh, login, or paid request. */
    async status() {
      const existing = await read();
      return {signedIn: !!existing, needsReconnect: !existing, accessExpired: !!existing && existing.expiresAt <= d.now()};
    },
    /** Deliberate review only. Display local suggestions first. Never await this during save. */
    async refine(selection: JevSelection, policy: JevPolicy, options: {signal?: AbortSignal; stillCurrent: () => boolean; beforeSend?: () => Promise<boolean>; deadlineMs?: number}): Promise<JevResult> {
      if (signingIn || signingOut) return fallback('authentication_busy');
      if (policy.jevEnabled !== true) return fallback('disabled');
      if (policy.jevConsentPageData !== true) return fallback('consent_required');
      const controller = new AbortController(), cancel = () => controller.abort();
      options.signal?.addEventListener('abort', cancel, {once: true}); if (options.signal?.aborted) cancel();
      const generation = epoch;
      const current = () => !controller.signal.aborted && !signingOut && generation === epoch && options.stillCurrent();
      const requestedDeadline = options.deadlineMs ?? 1000;
      const deadline = Number.isFinite(requestedDeadline) ? Math.max(1, Math.min(requestedDeadline, 1000)) : 1000;
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        if (!current()) return fallback('stale_or_canceled');
        const body = payload(selection, policy), input = JSON.parse(body) as JevSelection;
        const operation = (async (): Promise<JevResult> => {
          const auth = await session(); if (!current()) return fallback('stale_or_canceled');
          if (!auth) return fallback('reconnect_required');
          if (options.beforeSend && !await options.beforeSend()) return fallback('consent_changed');
          if (!current()) return fallback('stale_or_canceled');
          const response = await json('/v1/refine', {method: 'POST', headers: {'Content-Type': 'application/json', Authorization: `Bearer ${auth.access}`}, body}, controller.signal, deadline);
          if (!current()) return fallback('stale_or_canceled');
          if (response.status === 401) {await d.storage.remove(SESSION_KEY); return fallback('reconnect_required');}
          if (response.status !== 200) return fallback('unavailable');
          const v = record(response.body, ['version', 'available', 'fallback', 'reason', 'requestID', 'selectionVersion', 'purpose', 'candidates']);
          if (v.available === false && v.version === 1 && v.fallback === 'local') return fallback('unavailable');
          record(v, ['version', 'available', 'requestID', 'selectionVersion', 'purpose', 'candidates']);
          if (v.version !== 1 || v.available !== true || v.requestID !== input.requestID || v.selectionVersion !== input.selectionVersion || v.purpose !== input.purpose || !Array.isArray(v.candidates) || v.candidates.length > (input.purpose==='steps'?32:16)) throw Error('invalid');
          const allowed = new Set((input.purpose === 'steps' ? input.timeline : input.candidates).map(c => c.id)), seen = new Set<string>();
          const candidates = v.candidates.map(value => {
            const row = record(value, ['id', 'confidence']), id = identifier(row.id);
            if (!allowed.has(id) || seen.has(id) || typeof row.confidence !== 'number' || !Number.isFinite(row.confidence) || row.confidence < 0 || row.confidence > 1) throw Error('invalid');
            seen.add(id); return {id, confidence: row.confidence};
          });
          return current() ? {available: true, candidates} : fallback('stale_or_canceled');
        })();
        const stopped = new Promise<JevResult>(resolve => {
          controller.signal.addEventListener('abort', () => resolve(fallback('stale_or_canceled')), {once: true});
          timer = setTimeout(cancel, deadline);
        });
        return await Promise.race([operation, stopped]);
      } catch {return fallback('unavailable');}
      finally {if (timer) clearTimeout(timer); options.signal?.removeEventListener('abort', cancel);}
    },
  };
}
