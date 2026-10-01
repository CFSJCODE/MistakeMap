import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { allowedPath } from './verification/apply-policy.mjs';

const base = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(base, '../..');
const staged = path.join(base, 'staged');
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const manifestFile = path.join(base, 'manifest.json');
if (!fs.existsSync(manifestFile)) throw new Error('Manifesto de revisão ainda não foi fechado.');
const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
let config = null;
try { config = JSON.parse(fs.readFileSync(path.join(root, '.reversa/reversa-config.json'), 'utf8')); } catch { /* fail closed */ }

function safeTarget(directory, relative) {
  const result = path.resolve(directory, relative);
  const rel = path.relative(directory, result);
  if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) throw new Error('Caminho inválido.');
  for (let current = result; current !== directory; current = path.dirname(current)) {
    if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink()) throw new Error('Links não são permitidos.');
  }
  return result;
}

const checks = manifest.files.map(entry => {
  const source = safeTarget(staged, entry.path);
  const target = safeTarget(root, entry.path);
  if (digest(fs.readFileSync(source)) !== entry.staged_sha256) throw new Error(`Preparação mudou: ${entry.path}`);
  const current = fs.existsSync(target) ? digest(fs.readFileSync(target)) : null;
  return {...entry, source, target, allowed:allowedPath(config,entry.path), unchanged:current === entry.original_sha256};
});
console.log(JSON.stringify({mode:process.argv.includes('--apply')?'apply':'preview', files:checks.map(({path:p,allowed,unchanged})=>({path:p,allowed,unchanged}))},null,2));
if (!checks.every(item => item.allowed && item.unchanged)) {
  console.error('Aplicação bloqueada: libere somente os caminhos necessários e resolva eventuais mudanças concorrentes. Nenhum arquivo foi aplicado.');
  process.exitCode = 2;
} else if (process.argv.includes('--apply')) {
  const backup = path.join(base, 'backups', `${new Date().toISOString().replaceAll(':','-')}-${crypto.randomUUID()}`);
  fs.mkdirSync(backup,{recursive:true});
  for (const entry of checks) {
    if (entry.original_sha256 !== null) {
      const copy = safeTarget(backup,entry.path);
      fs.mkdirSync(path.dirname(copy),{recursive:true});
      fs.copyFileSync(entry.target,copy);
    }
  }
  fs.writeFileSync(path.join(backup,'manifest.json'),JSON.stringify(manifest,null,2));
  const applied = [];
  try {
    for (const entry of checks) {
      fs.mkdirSync(path.dirname(entry.target),{recursive:true});
      fs.copyFileSync(entry.source,entry.target);
      applied.push(entry.path);
    }
  } finally {
    fs.writeFileSync(path.join(backup,'applied.json'),JSON.stringify(applied,null,2));
  }
  console.log(`Arquivos aplicados: ${applied.length}. Backup: ${backup}`);
  console.log('Nenhuma migração, deploy, segredo ou operação Git foi executada.');
}
