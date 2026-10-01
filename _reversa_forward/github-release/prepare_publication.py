"""Select app changes and inspect publication candidates without logging values."""
from pathlib import Path
import base64
import json
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
out = Path(__file__).resolve().parent

def git(*args):
    return subprocess.check_output(
        ['git', '-c', 'core.safecrlf=false', *args], cwd=root,
        text=True, encoding='utf-8', errors='replace',
    )

paths = set()
if '--committed' in sys.argv:
    for path in git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').splitlines():
        paths.add(path)
for row in git('diff', '--ignore-space-at-eol', '--numstat').splitlines():
    parts = row.split('\t', 2)
    if len(parts) == 3 and parts[2].startswith('appmistakemap/') and parts[2].endswith('.dart'):
        paths.add(parts[2])
for row in git('diff', '--cached', '--ignore-space-at-eol', '--numstat').splitlines():
    parts = row.split('\t', 2)
    if len(parts) == 3 and parts[2].startswith('appmistakemap/') and parts[2].endswith('.dart'):
        paths.add(parts[2])
for path in git('ls-files', '--others', '--exclude-standard', '--', 'appmistakemap').splitlines():
    if path.endswith('.dart') and path.startswith(('appmistakemap/lib/', 'appmistakemap/test/')):
        paths.add(path)
monitor = root / '_reversa_forward/admin-monitoring'
for path in monitor.rglob('*'):
    if path.is_file() and path.suffix in {'.sql', '.ts', '.json', '.dart'}:
        paths.add(path.relative_to(root).as_posix())
readme = monitor / 'README.md'
if readme.exists():
    paths.add(readme.relative_to(root).as_posix())

patterns = {
    'private-key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'google-api-key': re.compile(r'AIza[0-9A-Za-z_-]{35}'),
    'openai-key': re.compile(r'\bsk-(?:proj-)?[A-Za-z0-9_-]{35,}'),
    'github-token': re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{35,})'),
    'aws-access-key': re.compile(r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'supabase-secret-key': re.compile(r'\bsb_secret_[A-Za-z0-9_-]{20,}'),
}
jwt = re.compile(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}')
findings = []
public_anon = 0
for name in sorted(paths):
    body = (root / name).read_text(encoding='utf-8-sig', errors='replace')
    for number, line in enumerate(body.splitlines(), 1):
        for rule, pattern in patterns.items():
            if pattern.search(line):
                findings.append({'file': name, 'line': number, 'rule': rule})
        for match in jwt.finditer(line):
            try:
                encoded = match.group().split('.')[1]
                payload = json.loads(base64.urlsafe_b64decode(encoded + '=' * (-len(encoded) % 4)))
            except (ValueError, UnicodeError):
                findings.append({'file': name, 'line': number, 'rule': 'unclassified-jwt'})
                continue
            if payload.get('role') == 'anon':
                public_anon += 1
            else:
                findings.append({'file': name, 'line': number, 'rule': 'non-public-jwt'})

manifest = ''.join(path + '\n' for path in sorted(paths))
(out / 'publication-paths.txt').write_text(manifest, encoding='utf-8')
summary = {'files': len(paths), 'public_anon_keys': public_anon, 'findings': findings}
(out / 'secret-review.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(json.dumps(summary))
raise SystemExit(1 if findings else 0)
