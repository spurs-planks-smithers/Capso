import {safeFileName} from './sanitize.ts';
const crcTable=Uint32Array.from({length:256},(_,n)=>{for(let j=0;j<8;j++)n=n&1?0xedb88320^(n>>>1):n>>>1;return n>>>0;});
function crc32(bytes:Uint8Array):number {let n=0xffffffff;for(const b of bytes)n=crcTable[(n^b)&255]^(n>>>8);return (n^0xffffffff)>>>0;}
function words(size:number,values:[number,number,2|4][]):Uint8Array {
  const a=new Uint8Array(size),v=new DataView(a.buffer);
  for(const [at,n,bytes] of values)bytes===2?v.setUint16(at,n,true):v.setUint32(at,n,true);
  return a;
}
export function zipFiles(files:{name:string;bytes:Uint8Array}[]):Uint8Array {
  if(!files.length||files.length>4096)throw new Error('Invalid export files');
  const names=new Set<string>(),parts:Uint8Array[]=[],central:Uint8Array[]=[];
  let offset=0,centralSize=0,total=0;
  for(const file of files){
    safeFileName(file.name);if(names.has(file.name))throw new Error('Duplicate export name');names.add(file.name);
    total+=file.bytes.length;if(total>128*1024*1024)throw new Error('Export exceeds safe processing limit');
    const name=new TextEncoder().encode(file.name),crc=crc32(file.bytes),length=file.bytes.length;
    const local=words(30,[[0,0x04034b50,4],[4,20,2],[6,0x800,2],[12,0x21,2],[14,crc,4],[18,length,4],[22,length,4],[26,name.length,2]]);
    parts.push(local,name,file.bytes);
    const entry=words(46,[[0,0x02014b50,4],[4,20,2],[6,20,2],[8,0x800,2],[14,0x21,2],[16,crc,4],[20,length,4],[24,length,4],[28,name.length,2],[42,offset,4]]);
    central.push(entry,name);centralSize+=entry.length+name.length;offset+=local.length+name.length+length;
  }
  const end=words(22,[[0,0x06054b50,4],[8,files.length,2],[10,files.length,2],[12,centralSize,4],[16,offset,4]]);
  const all=[...parts,...central,end],output=new Uint8Array(offset+centralSize+end.length);let at=0;
  for(const part of all){output.set(part,at);at+=part.length;}
  return output;
}
