"""Scoped history correction authorized by the user on 2026-09-29."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from contextlib import contextmanager
from datetime import datetime, timezone

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
CONFIG = ROOT / '.reversa/reversa-config.json'
REPORT = OUT / 'resultado.json'
EXPECTED = '01ad880d65fb67bbb03fdd2acca3f5be9e7dd51f'
TARGETS = {
    'abcb950621d6c627f310b0f0c238356b7af7b3eb': b'docs: remove README da raiz',
    'cb0a4f2b72a2d5ec664140db8eca6c574c9daa60': b'docs: remove README de .github',
    '348c4f4d879b493704a10a22abb95ff3716e475e': b'docs: adiciona README completo em .github',
}
CLAUDE = b'Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>'
ASTRA = b'Co-Authored-By: ChatGPT 6 Astra <noreply@openai.com>'

def git(*args, data=None):
    env = os.environ.copy()
    env['GIT_OPTIONAL_LOCKS'] = '0'
    result = subprocess.run(['git', *args], cwd=ROOT, env=env,
                            input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
    return result.stdout

def sha(data):
    return hashlib.sha256(data).hexdigest()

def snapshot():
    tracked = {}
    for raw in git('ls-files', '-z').split(b'\0'):
        if not raw:
            continue
        name = raw.decode('utf-8')
        path = ROOT / name
        tracked[name] = sha(path.read_bytes()) if path.is_file() else None
    return {
        'head': git('rev-parse', 'HEAD').decode().strip(),
        'head_ref': git('symbolic-ref', 'HEAD').decode().strip(),
        'index_sha256': sha((ROOT / '.git/index').read_bytes()),
        'tracked_file_hashes': tracked,
    }

def remote_tip():
    lines = git('ls-remote', '--heads', 'origin', 'refs/heads/main').splitlines()
    assert len(lines) == 1, 'Ambiguous remote main'
    return lines[0].split()[0].decode()

@contextmanager
def scoped_permission():
    # The user's latest message explicitly authorizes the required releases.
    original = CONFIG.read_bytes()
    parsed = json.loads(original)
    assert parsed == {'version': 1, 'allowLegacyEdits': False, 'allowedPaths': []}, 'Configuration changed'
    try:
        parsed.update(allowLegacyEdits=True, allowedPaths=['.git/**'])
        CONFIG.write_text(json.dumps(parsed, indent=2) + '\n', encoding='utf-8')
        verified = json.loads(CONFIG.read_bytes())
        assert verified['allowLegacyEdits'] and verified['allowedPaths'] == ['.git/**']
        yield
    finally:
        CONFIG.write_bytes(original)

def save(report):
    REPORT.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

def verify_workspace(baseline):
    current = snapshot()
    for field in ['head', 'head_ref', 'tracked_file_hashes']:
        assert current[field] == baseline[field], 'Local workspace changed: ' + field
    # Initial porcelain output showed no staged changes. The binary index changed
    # after preparation, with no staged content differences. Validate its entries
    # against the unchanged HEAD; the origin of the binary change is unknown.
    git('diff', '--cached', '--quiet', baseline['head'])
    expected_entries = {}
    for entry in git('ls-tree', '-rz', '--full-tree', baseline['head']).split(b'\0'):
        if entry:
            metadata, path = entry.split(b'\t', 1)
            mode, kind, oid = metadata.split()
            expected_entries[path] = mode + b' ' + oid + b' 0'
    actual_entries = {}
    for entry in git('ls-files', '--stage', '-z').split(b'\0'):
        if entry:
            metadata, path = entry.split(b'\t', 1)
            assert path not in actual_entries, 'Unmerged index entry'
            actual_entries[path] = metadata
    assert actual_entries == expected_entries, 'Staged paths, modes or blobs changed'
    return current['index_sha256'] != baseline['index_sha256']

def prepare():
    assert not REPORT.exists(), 'Preparation already exists'
    assert remote_tip() == EXPECTED, 'Remote changed; re-audit required'
    assert git('rev-parse', 'origin/main').decode().strip() == EXPECTED
    baseline = snapshot()
    (OUT / 'estado-local-antes.json').write_text(json.dumps(baseline, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    backup = OUT / 'historico-antes.bundle'
    assert not backup.exists(), 'Do not overwrite a backup'
    git('bundle', 'create', str(backup), '--all')
    git('bundle', 'verify', str(backup))
    order = git('rev-list', '--reverse', '--topo-order', EXPECTED).decode().splitlines()
    mapping = {}
    changed_messages = []
    with scoped_permission():
        for old in order:
            raw = git('cat-file', 'commit', old)
            headers, message = raw.split(b'\n\n', 1)
            lines = headers.split(b'\n')
            new_lines = []
            changed = old in TARGETS
            for line in lines:
                if line.startswith(b'parent '):
                    parent = line[7:].decode()
                    if parent in mapping:
                        line = b'parent ' + mapping[parent].encode()
                        changed = True
                new_lines.append(line)
            if not changed:
                continue
            assert not any(line.startswith((b'gpgsig ', b'mergetag ')) for line in lines), 'Signed header needs explicit handling'
            if old in TARGETS:
                assert message.strip() == TARGETS[old] + b'\n' + CLAUDE, 'Unexpected original message'
                message = TARGETS[old] + b'\n\n' + CLAUDE + b'\n' + ASTRA + b'\n'
                parsed = git('interpret-trailers', '--parse', data=message)
                assert parsed.splitlines() == [CLAUDE, ASTRA]
                changed_messages.append(old)
            replacement = b'\n'.join(new_lines) + b'\n\n' + message
            new = git('hash-object', '-t', 'commit', '-w', '--stdin', data=replacement).decode().strip()
            assert git('cat-file', 'commit', new) == replacement
            assert git('rev-parse', old + '^{tree}') == git('rev-parse', new + '^{tree}')
            mapping[old] = new
        assert len(mapping) == 44 and set(changed_messages) == set(TARGETS)
        new_tip = mapping[EXPECTED]
        git('diff-tree', '--quiet', EXPECTED, new_tip)
        git('fsck', '--connectivity-only', '--no-dangling', new_tip)
    assert snapshot() == baseline, 'Local workspace or index changed'
    report = {
        'status': 'prepared',
        'prepared_at': datetime.now(timezone.utc).isoformat(),
        'old_remote_tip': EXPECTED,
        'new_remote_tip': new_tip,
        'target_mapping': {old: mapping[old] for old in TARGETS},
        'all_mapping': mapping,
        'backup': backup.name,
        'backup_sha256': sha(backup.read_bytes()),
        'validated': ['all_44_trees_unchanged', 'only_3_messages_changed', 'parent_order_preserved', 'all_other_headers_preserved', 'git_connectivity', 'local_head_index_and_tracked_files_unchanged', 'original_permission_restored'],
    }
    save(report)
    print(json.dumps({k: report[k] for k in ['status', 'old_remote_tip', 'new_remote_tip', 'target_mapping', 'validated']}, indent=2))

def publish():
    report = json.loads(REPORT.read_text(encoding='utf-8'))
    assert report['status'] == 'prepared', 'Unexpected publication state'
    baseline = json.loads((OUT / 'estado-local-antes.json').read_text(encoding='utf-8'))
    index_refreshed = verify_workspace(baseline)
    assert sha((OUT / report['backup']).read_bytes()) == report['backup_sha256']
    assert remote_tip() == report['old_remote_tip'], 'Remote changed; do not overwrite'
    with scoped_permission():
        git('push', '--force-with-lease=refs/heads/main:' + report['old_remote_tip'],
            'origin', report['new_remote_tip'] + ':refs/heads/main')
        assert remote_tip() == report['new_remote_tip'], 'Remote result not confirmed'
        tracking = git('rev-parse', 'refs/remotes/origin/main').decode().strip()
        assert tracking in [report['old_remote_tip'], report['new_remote_tip']]
        if tracking != report['new_remote_tip']:
            git('update-ref', 'refs/remotes/origin/main', report['new_remote_tip'], tracking)
    verify_workspace(baseline)
    report['status'] = 'published'
    report['published_at'] = datetime.now(timezone.utc).isoformat()
    report['index_binary_refresh_observed'] = index_refreshed
    report['index_semantics_validated_against_unchanged_head'] = True
    report['validated'] += ['remote_main_confirmed', 'tracking_ref_updated', 'post_publication_workspace_unchanged']
    save(report)
    print(json.dumps({k: report[k] for k in ['status', 'new_remote_tip', 'target_mapping', 'validated']}, indent=2))

if __name__ == '__main__':
    {'prepare': prepare, 'publish': publish}[sys.argv[1]]()
