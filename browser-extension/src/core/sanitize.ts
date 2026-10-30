export function sanitizeText(value:unknown,max=1000):string {
  return typeof value==='string'?value.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g,'').slice(0,max):'';
}
export function redactSensitive(value:unknown,max=1000):string {
  return sanitizeText(value,max)
    .replace(/\bBearer\s+[A-Za-z0-9._~+\/-]{8,}/gi,'Bearer [redacted]')
    .replace(/\b(?:sk|pk|api)[_-][A-Za-z0-9_-]{16,}/g,'[redacted]')
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g,'[redacted]')
    .replace(/\b(password|secret|token|authorization|api[_-]?key)\s*[:=]\s*[^\s,;]+/gi,'$1=[redacted]');
}
export function sanitizeURL(value:unknown):string|undefined {
  if(typeof value!=='string'||value.length>8192)return;
  try {
    const url=new URL(value);
    if(!['http:','https:'].includes(url.protocol))return;
    url.username='';url.password='';url.search='';url.hash='';
    url.pathname=url.pathname.split('/').map(segment=>segment.length>48||/^(?:sk[_-]|eyJ)/.test(segment)?'[redacted]':segment).join('/');
    return url.toString();
  }catch{return;}
}
export function safeFileName(value:unknown):string {
  if(typeof value!=='string'||!value||value.length>160||!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value)||value.includes('..'))throw new Error('Unsafe asset name');
  return value;
}
