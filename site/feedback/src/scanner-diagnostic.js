import {
  ensureScannerRuntime,
  waitForScannerReady,
  startupSignal,
} from "./scanner-runtime.js";
const FLAGS = [
  "INTAKE_ENABLED",
  "NATIVE_ENABLED",
  "PROCESSING_ENABLED",
  "AI_SCREENING_ENABLED",
  "EMAIL_ENABLED",
  "NOTIFICATIONS_ENABLED",
];
const FIELDS = [
  "tcpBlocked",
  "httpsBlocked",
  "signatureMatched",
  "credentialsAbsent",
];
const PHASES = Object.freeze({
  manifest: "diagnostic_manifest_failed",
  runtime: "diagnostic_runtime_failed",
  readiness: "diagnostic_readiness_failed",
  inspect: "diagnostic_inspect_failed",
  exec: "diagnostic_exec_failed",
  stdout: "diagnostic_stdout_failed",
  exit: "diagnostic_exit_failed",
});
const failure = (error, image = null) => ({
  ok: false,
  ...Object.fromEntries(FIELDS.map((key) => [key, false])),
  image,
  error,
});
const invalid = (code) => {
  throw Object.assign(new Error(code), { code });
};
export const ISOLATION_SCRIPT = String.raw`import hashlib,json,os,re,signal,socket,sys,urllib.error,urllib.request

def expired(*_): raise SystemExit(124)
signal.signal(signal.SIGALRM,expired)
signal.alarm(12)
result={'tcpBlocked':False,'httpsBlocked':False,'signatureMatched':False,'credentialsAbsent':False}
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*_): return None
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
try:
 with socket.create_connection(('1.1.1.1',443),timeout=2): pass
except OSError: result['tcpBlocked']=True
try:
 with opener.open('https://example.com',timeout=2): pass
except urllib.error.HTTPError: pass
except Exception: result['httpsBlocked']=True
try:
 item=json.loads(sys.stdin.read(4097))
 assert set(item)=={'name','sha256','bytes'} and item['name']=='bytecode.cvd'
 assert isinstance(item['sha256'],str) and re.fullmatch('[a-f0-9]{64}',item['sha256'])
 assert type(item['bytes']) is int and 0<item['bytes']<=10000000
 digest=hashlib.sha256(); size=0
 url='http://signatures.nextshot.internal/'+item['sha256']+'/bytecode.cvd'
 with opener.open(url,timeout=5) as response:
  while True:
   chunk=response.read(min(65536,item['bytes']-size+1))
   if not chunk: break
   size+=len(chunk)
   if size>item['bytes']: raise ValueError()
   digest.update(chunk)
 result['signatureMatched']=size==item['bytes'] and digest.hexdigest()==item['sha256']
except Exception: pass
try:
 with open('/proc/1/environ','rb') as source: process_env=source.read(65537)
 assert len(process_env)<=65536
 names=list(os.environ)+[part.split(b'=',1)[0].decode('ascii') for part in process_env.split(b'\x00') if b'=' in part]
 sensitive=re.compile(r'(^|_)(TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIALS?|API_KEY|ACCESS_KEY(_ID)?|PRIVATE_KEY)$')
 result['credentialsAbsent']=not any(sensitive.search(name.upper()) for name in names)
except Exception: pass
signal.alarm(0)
print(json.dumps(result,separators=(',',':')))
`;
async function signature(env) {
  const object = await env.SIGNATURES?.get("manifest.json");
  if (!object || object.size > 4096) invalid("signature_manifest_unavailable");
  const bytes = new Uint8Array(await object.arrayBuffer());
  if (bytes.length > 4096) invalid("signature_manifest_unavailable");
  let value;
  try {
    value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    invalid("signature_manifest_unavailable");
  }
  const names = ["main.cvd", "daily.cvd", "bytecode.cvd"];
  if (
    value?.version !== 1 ||
    !Array.isArray(value.files) ||
    value.files.length !== 3 ||
    new Set(value.files.map((file) => file?.name)).size !== 3 ||
    value.files.some(
      (file) =>
        !names.includes(file?.name) ||
        typeof file.sha256 !== "string" ||
        !/^[a-f0-9]{64}$/.test(file.sha256) ||
        !Number.isSafeInteger(file.bytes) ||
        file.bytes < 1 ||
        file.bytes > 300000000,
    )
  )
    invalid("signature_manifest_unavailable");
  const file = value.files.find((file) => file.name === "bytecode.cvd");
  if (file.bytes > 10000000) invalid("signature_manifest_unavailable");
  return { name: file.name, sha256: file.sha256, bytes: file.bytes };
}
async function readResult(stream) {
  if (!stream) invalid("diagnostic_result_invalid");
  const reader = stream.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.byteLength;
      if (size > 1024) invalid("diagnostic_result_invalid");
      chunks.push(part.value);
    }
  } catch (error) {
    reader.cancel().catch(() => {});
    throw error;
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let parsed;
  try {
    parsed = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
  } catch {
    invalid("diagnostic_result_invalid");
  }
  if (
    !parsed ||
    Array.isArray(parsed) ||
    Object.keys(parsed).length !== FIELDS.length ||
    FIELDS.some((key) => typeof parsed[key] !== "boolean")
  )
    invalid("diagnostic_result_invalid");
  return parsed;
}
export async function verifyScannerIsolation(
  managed,
  ctx,
  env,
  argumentCount = 0,
) {
  if (!FLAGS.every((flag) => env?.[flag] === "false"))
    return failure("diagnostic_disabled");
  if (argumentCount !== 0) return failure("diagnostic_arguments_forbidden");
  if (managed.scanning) return failure("scanner_busy");
  managed.scanning = true;
  let image = null,
    process,
    timer,
    exited = false,
    killed = false,
    stage = PHASES.manifest;
  const stop = () => {
    if (process && !exited && !killed) {
      killed = true;
      process.kill(9);
    }
  };
  try {
    if (typeof ctx.container?.exec !== "function")
      invalid("scanner_exec_unavailable");
    const file = await signature(env);
    stage = PHASES.runtime;
    const startup = startupSignal();
    await ensureScannerRuntime(ctx, startup);
    image = ctx.container.images.scanner;
    stage = PHASES.readiness;
    await waitForScannerReady(ctx, startup);
    stage = PHASES.inspect;
    const info = await ctx.container.inspect();
    if (info?.image !== image) invalid("scanner_image_unavailable");
    const deadline = new Promise((_, reject) => {
      timer = setTimeout(() => {
        try {
          stop();
        } catch {}
        reject(
          Object.assign(new Error("diagnostic_timeout"), {
            code: "diagnostic_timeout",
          }),
        );
      }, 15000);
    });
    const result = await Promise.race([
      deadline,
      (async () => {
        stage = PHASES.exec;
        process = await ctx.container.exec(["python", "-c", ISOLATION_SCRIPT], {
          stdin: new Response(JSON.stringify(file)).body,
          stdout: "pipe",
          stderr: "ignore",
          env: {},
        });
        stage = PHASES.stdout;
        const [values, exit] = await Promise.all([
          readResult(process.stdout).catch((error) => {
            if (error?.code) throw error;
            invalid(PHASES.stdout);
          }),
          Promise.resolve(process.exitCode).then(
            (value) => {
              exited = true;
              return value;
            },
            () => {
              exited = true;
              invalid(PHASES.exit);
            },
          ),
        ]);
        if (exit !== 0)
          invalid(
            exit === 124 ? "diagnostic_timeout" : "diagnostic_process_failed",
          );
        return values;
      })(),
    ]);
    const ok = FIELDS.every((key) => result[key]);
    return {
      ok,
      ...result,
      image,
      error: ok ? null : "isolation_check_failed",
    };
  } catch (error) {
    try {
      stop();
    } catch {}
    return failure(
      [
        "signature_manifest_unavailable",
        "scanner_exec_unavailable",
        "scanner_image_unavailable",
        "diagnostic_timeout",
        "diagnostic_result_invalid",
        "diagnostic_process_failed",
        ...Object.values(PHASES),
      ].includes(error?.code)
        ? error.code
        : Object.values(PHASES).includes(stage)
          ? stage
          : "diagnostic_failed",
      image,
    );
  } finally {
    clearTimeout(timer);
    managed.scanning = false;
  }
}
