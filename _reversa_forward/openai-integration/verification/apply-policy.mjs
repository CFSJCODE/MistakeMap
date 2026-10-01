import path from 'node:path';

export function allowedPath(config, relative) {
  if (!relative || relative.includes('\\') || path.posix.isAbsolute(relative) ||
      relative.split('/').some(part => part === '..' || part === '.' || !part) ||
      relative.includes(':') || relative === '.reversa/reversa-config.json') return false;
  if (!config || config.allowLegacyEdits !== true) return false;
  if (config.allowedPaths !== undefined && (!Array.isArray(config.allowedPaths) ||
      config.allowedPaths.some(item => typeof item !== 'string'))) return false;
  const globs = config.allowedPaths ?? [];
  if (!globs.length) return true;
  return globs.some(glob => {
    let expression = '';
    for (let i = 0; i < glob.length; i++) {
      const character = glob[i];
      if (character === '*' && glob[i + 1] === '*') { expression += '.*'; i++; }
      else if (character === '*') expression += '[^/]*';
      else expression += /[\\^$+?.()|[\]{}]/.test(character) ? `\\${character}` : character;
    }
    return new RegExp(`^${expression}$`).test(relative);
  });
}
