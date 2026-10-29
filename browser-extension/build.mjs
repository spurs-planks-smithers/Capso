import {build} from 'esbuild';
import {mkdir, readdir, copyFile, stat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const root=path.dirname(fileURLToPath(import.meta.url));
const pilot=process.argv.includes('--pilot');
const output=path.resolve(root,pilot?'../build/chrome-pilot':'../build/chrome-extension');
const define={__NEXTSHOT_BROWSER_ONLY__:String(pilot)};
await mkdir(output,{recursive:true});
const names=await readdir(path.join(root,'src'));
const entries=(pilot?['pilot-background.ts','pilot-popup.ts','review.ts']:names.filter(n=>n.endsWith('.ts')&&n!=='content.ts'&&n!=='capture.ts'&&!n.startsWith('pilot-'))).map(n=>path.join(root,'src',n));
if(entries.length)await build({entryPoints:entries,outdir:output,bundle:true,format:'esm',target:'chrome120',minify:false,minifySyntax:pilot,sourcemap:false,define});
if(names.includes('content.ts'))await build({entryPoints:[path.join(root,'src/content.ts')],outfile:path.join(output,'content.js'),bundle:true,format:'iife',target:'chrome120',define});
await build({entryPoints:[path.join(root,'src/core/index.ts')],outfile:path.join(output,'core.js'),bundle:true,format:'esm',target:'chrome120'});
for(const name of await readdir(root)){
  if(name===(pilot?'pilot-manifest.json':'manifest.json'))await copyFile(path.join(root,name),path.join(output,'manifest.json'));
}
async function copyAssets(directory,destination){
  let items;try{items=await readdir(directory);}catch(e){if(e.code==='ENOENT')return;throw e;}
  await mkdir(destination,{recursive:true});
  for(const name of items){
    if(name==='pilot-popup.html')continue;
    const source=path.join(directory,name),target=path.join(destination,name);
    if((await stat(source)).isDirectory())await copyAssets(source,target);else await copyFile(source,target);
  }
}
if(pilot){
  for(const name of ['style.css','review.html'])await copyFile(path.join(root,'public',name),path.join(output,name));
  await copyFile(path.join(root,'public/pilot-popup.html'),path.join(output,'popup.html'));
}else await copyAssets(path.join(root,'public'),output);
console.log(`Nextshot browser build: ${output}`);
