import {build} from 'esbuild';
import {mkdir, readdir, copyFile, stat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root=path.dirname(fileURLToPath(import.meta.url));
const output=path.resolve(root,'../build/chrome-extension');
await mkdir(output,{recursive:true});
const names=await readdir(path.join(root,'src'));
const entries=names.filter(n=>n.endsWith('.ts')).map(n=>path.join(root,'src',n));
if(entries.length)await build({entryPoints:entries,outdir:output,bundle:true,format:'esm',target:'chrome120',minify:false,sourcemap:false});
await build({entryPoints:[path.join(root,'src/core/index.ts')],outfile:path.join(output,'core.js'),bundle:true,format:'esm',target:'chrome120'});
for(const name of await readdir(root)){
  if(name==='manifest.json')await copyFile(path.join(root,name),path.join(output,name));
}
async function copyAssets(directory,destination){
  let items;try{items=await readdir(directory);}catch(e){if(e.code==='ENOENT')return;throw e;}
  await mkdir(destination,{recursive:true});
  for(const name of items){
    const source=path.join(directory,name),target=path.join(destination,name);
    if((await stat(source)).isDirectory())await copyAssets(source,target);else await copyFile(source,target);
  }
}
await copyAssets(path.join(root,'public'),output);
console.log(`Nextshot browser build: ${output}`);
