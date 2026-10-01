import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const base=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const root=path.resolve(base,'../..');
const stage=path.join(base,'staged');
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const files=[];
function walk(dir,relative='') {
  for(const entry of fs.readdirSync(dir,{withFileTypes:true})) {
    if(entry.isSymbolicLink()) throw new Error('Preparação contém link.');
    const rel=relative?`${relative}/${entry.name}`:entry.name;
    if(entry.isDirectory()) {
      if(['.dart_tool','build','.git','node_modules','previews','.temp'].includes(entry.name)) continue;
      walk(path.join(dir,entry.name),rel);
    } else if(entry.isFile()) {
      const selected=/^appmistakemap\/(lib|test)\/.*\.dart$/.test(rel) ||
        /^appmistakemap\/pubspec\.(yaml|lock)$/.test(rel) ||
        /^supabase\/functions\/.*\.(ts|json|lock)$/.test(rel) ||
        /^supabase\/migrations\/.*\.sql$/.test(rel);
      if(!selected) continue;
      const original=path.join(root,rel);
      const stagedHash=hash(fs.readFileSync(path.join(stage,rel)));
      const originalHash=fs.existsSync(original)?hash(fs.readFileSync(original)):null;
      if(stagedHash===originalHash) continue;
      files.push({path:rel,change:originalHash===null?'new':'modified',original_sha256:originalHash,staged_sha256:stagedHash});
    }
  }
}
walk(stage);
files.sort((a,b)=>a.path.localeCompare(b.path));
fs.writeFileSync(path.join(base,'manifest.json'),JSON.stringify({version:1,created_at:new Date().toISOString(),state:'prepared_not_applied',files},null,2)+'\n');
console.log(JSON.stringify({files:files.length,modified:files.filter(f=>f.change==='modified').length,new:files.filter(f=>f.change==='new').length}));
