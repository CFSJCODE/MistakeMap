import test from 'node:test';
import assert from 'node:assert/strict';
import { allowedPath } from './apply-policy.mjs';

test('closed or malformed policy never grants writes', () => {
  for (const config of [null, {}, {allowLegacyEdits:false}, {allowLegacyEdits:'true'},
    {allowLegacyEdits:true,allowedPaths:'**'}, {allowLegacyEdits:true,allowedPaths:[7]}]) {
    assert.equal(allowedPath(config, 'appmistakemap/lib/main.dart'), false);
  }
});
test('scoped policy blocks traversal, prefix confusion and config mutation', () => {
  const policy = {allowLegacyEdits:true,allowedPaths:['appmistakemap/**','supabase/**','BACKEND.md']};
  for (const p of ['../appmistakemap/lib/main.dart','appmistakemap/../secret','appmistakemap-fake/a.dart',
    'supabase\\a.ts','C:/supabase/a.ts','/supabase/a.ts','.reversa/reversa-config.json','BACKENDXmd']) {
    assert.equal(allowedPath(policy,p),false,p);
  }
  for (const p of ['appmistakemap/lib/main.dart','supabase/functions/example/index.ts','BACKEND.md']) {
    assert.equal(allowedPath(policy,p),true,p);
  }
});
test('single star cannot span directories and double star can', () => {
  assert.equal(allowedPath({allowLegacyEdits:true,allowedPaths:['supabase/*']},'supabase/a/b.ts'),false);
  assert.equal(allowedPath({allowLegacyEdits:true,allowedPaths:['supabase/**']},'supabase/a/b.ts'),true);
});
test('unrestricted policy still refuses config changes and invalid target paths', () => {
  assert.equal(allowedPath({allowLegacyEdits:true},'appmistakemap/lib/main.dart'),true);
  assert.equal(allowedPath({allowLegacyEdits:true},'.reversa/reversa-config.json'),false);
  assert.equal(allowedPath({allowLegacyEdits:true},'x//y'),false);
});
