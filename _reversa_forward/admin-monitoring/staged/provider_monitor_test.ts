import { canonicalModel, monitoredFetch, type ProviderRecorder } from './functions/_shared/provider_monitor.ts';
function assert(value: unknown, message: string) { if (!value) throw new Error(message); }
Deno.test('records provider metadata without body or credentials, preserves response', async () => {
  let saved: Record<string, unknown> = {};
  let closed = false;
  const store: ProviderRecorder = {
    start: async () => 'event', finish: async (_, data) => { saved = {...data}; },
    close: async () => { closed = true; },
  };
  const payload = {modelVersion:'gemini-3.8-flash-preview',usageMetadata:{promptTokenCount:852,candidatesTokenCount:188,totalTokenCount:1040},candidates:[{content:{parts:[{text:'private student response'}]}}]};
  const fetcher = (async () => new Response(JSON.stringify(payload), {status:200})) as typeof fetch;
  const response = await monitoredFetch(fetcher, () => 'database-test', () => store)(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent', {headers:{'x-goog-api-key':'test-secret'}});
  assert(saved.model === 'gemini-3.8-flash', 'model comes from provider modelVersion');
  assert(saved.input_tokens===852 && saved.status_code===200, 'observed tokens and HTTP status');
  assert(!JSON.stringify(saved).includes('private') && !JSON.stringify(saved).includes('secret'), 'sensitive contents are excluded');
  assert(JSON.stringify(await response.json())===JSON.stringify(payload), 'original response remains available');
  assert(closed, 'connection released');
});
Deno.test('network failure stays a failure and missing tokens stay unknown', async () => {
  let saved: Record<string, unknown> = {};
  const store: ProviderRecorder = {start:async()=> 'event',finish:async(_,data)=>{saved={...data};},close:async()=>{}};
  let failed = false;
  try { await monitoredFetch((async()=>{throw new Error('network');}) as typeof fetch,()=> 'database-test',()=>store)(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent'); }
  catch { failed=true; }
  assert(failed && saved.status_code===0 && saved.input_tokens===null, 'does not swallow or fabricate usage');
  assert(canonicalModel('other-model')==='other-model','unrecognized models retain their identity');
});
