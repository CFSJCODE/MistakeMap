import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const stage = path.join(root, '_reversa_forward/openai-integration/staged');
const db = new PGlite();
const read = p => fs.readFileSync(path.join(root,p),'utf8');
const a = '10000000-0000-4000-8000-000000000001';
const b = '10000000-0000-4000-8000-000000000002';
const s1 = '20000000-0000-4000-8000-000000000001';
const s2 = '20000000-0000-4000-8000-000000000002';
const e1 = '30000000-0000-4000-8000-000000000001';
const e2 = '30000000-0000-4000-8000-000000000002';
const e3 = '30000000-0000-4000-8000-000000000003';
const p1 = '60000000-0000-4000-8000-000000000001';
const t1 = '40000000-0000-4000-8000-000000000001';
const t2 = '40000000-0000-4000-8000-000000000002';
const t3 = '40000000-0000-4000-8000-000000000003';
let passed = 0;
async function test(name, fn) { await fn(); passed++; console.log(`PASS ${name}`); }
async function denied(sql) { await assert.rejects(db.exec(sql), e => e.code === '42501'); }
async function asUser(id) { await db.exec(`reset role; select set_config('request.jwt.claim.sub','${id}',false); set role authenticated;`); }
try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create schema extensions;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    create function auth.role() returns text language sql stable as $$ select current_setting('role',true) $$;
    grant usage on schema auth,public to anon,authenticated,service_role;
    create function public.enforce_rate_limit() returns trigger language plpgsql as $$ begin return new; end $$;
  `);
  // PGlite has native gen_random_uuid; external pgcrypto and the preexisting
  // asset-rate-limit trigger are outside this test's scope, not newly modified.
  await db.exec(read('appmistakemap/database/supabase/migrations/20260901163259_create_initial_schema.sql')
    .replace('create extension if not exists "pgcrypto" with schema extensions;',''));
  await db.exec(read('appmistakemap/database/supabase/migrations/20260910023647_create_ingestion_pipeline_tables.sql'));
  await db.exec(read('appmistakemap/database/supabase/migrations/20260914120000_create_r2_quota_tracking.sql'));
  await db.exec('grant all on all tables in schema public to authenticated,service_role; grant usage,select on all sequences in schema public to authenticated,service_role;');
  const migration = process.argv[2] ? path.resolve(process.argv[2]) : path.join(stage,'supabase/change.sql');
  await test('prepared migration compiles on baseline schema', async()=>{ await db.exec(fs.readFileSync(migration,'utf8')); });
  await db.exec(`
    insert into auth.users values('${a}'),('${b}');
    insert into public.subjects(id,user_id,name) values('${s1}','${a}','Matemática A'),('${s2}','${b}','Matemática B');
    insert into public.exercises(id,subject_id,prompt_text) values('${e1}','${s1}','2+2?'),('${e2}','${s2}','3+3?');
    insert into public.attempts(id,exercise_id,user_id,answer,status) values('${t1}','${e1}','${a}','5','completed'),('${t2}','${e2}','${b}','7','completed'),('${t3}','${e1}','${a}','5','uploading');
    insert into public.attempt_analyses(attempt_id,user_id,subject_id,analysis,model,pipeline_version)
      values('${t1}','${a}','${s1}','{}','test-model','test'),('${t2}','${b}','${s2}','{}','test-model','test');
    insert into public.exercises(id,subject_id,prompt_text) values('${e3}','${s1}','5+5?');
    insert into public.practice_sets(id,user_id,subject_id,source_attempt_ids,exercise_count,model)
      values('${p1}','${a}','${s1}',array['${t1}'::uuid],3,'test-model');
    insert into public.practice_answer_keys(exercise_id,practice_set_id,correct_answer,explanation,focus_concept)
      values('${e3}','${p1}','10','Somar cinco a cinco.','Adição');
  `);
  await asUser(a);
  await test('student A reads only their own analysis',async()=>{const r=await db.query('select attempt_id from public.attempt_analyses'); assert.deepEqual(r.rows,[{attempt_id:t1}]);});
  await test('student cannot modify generated analysis',async()=>{ await denied("update public.attempt_analyses set analysis='{}'");});
  await test('generated answer keys are inaccessible to students',async()=>{ await denied('select * from public.practice_answer_keys');});
  await test('usage accounting is inaccessible to students',async()=>{ await denied('select * from public.ai_daily_usage');});
  await test('student cannot forge completed analysis state',async()=>{ await denied(`update public.attempts set status='completed' where id='${t3}'`);});
  await test('student cannot alter an analyzed answer',async()=>{ await denied(`update public.attempts set answer='4' where id='${t1}'`);});
  await test('submitted prompt cannot change underneath cached analysis',async()=>{ await denied(`update public.exercises set prompt_text='99+99?' where id='${e1}'`);});
  await test('generated prompt cannot change underneath its private answer key',async()=>{ await denied(`update public.exercises set prompt_text='99+99?' where id='${e3}'`);});
  await test('generated exercise subject cannot be reassigned',async()=>{ await denied(`update public.exercises set subject_id='${s2}' where id='${e3}'`);});
  await test('cross-user exercise submission is rejected',async()=>{ await denied(`insert into public.attempts(exercise_id,user_id,answer,status) values('${e2}','${a}','injected','pending')`);});
  await test('asset path cannot reference another student',async()=>{ await denied(`insert into public.attempt_assets(attempt_id,object_path,sha256) values('${t3}','uploads/${b}/50000000-0000-4000-8000-000000000001.jpg','${'a'.repeat(64)}')`);});
  await test('asset requires a real-format SHA256',async()=>{ await denied(`insert into public.attempt_assets(attempt_id,object_path,sha256) values('${t3}','uploads/${a}/50000000-0000-4000-8000-000000000001.jpg','not-a-sha256')`);});
  await test('student can finish valid own upload and version advances',async()=>{
    await db.exec(`insert into public.attempt_assets(attempt_id,object_path,sha256) values('${t3}','uploads/${a}/50000000-0000-4000-8000-000000000001.jpg','${'a'.repeat(64)}'); update public.attempts set status='pending' where id='${t3}';`);
    const r=await db.query(`select status,version from public.attempts where id='${t3}'`); assert.deepEqual(r.rows,[{status:'pending',version:2}]);
  });
  await asUser(b);
  await test('student B cannot see student A analysis',async()=>{const r=await db.query('select attempt_id from public.attempt_analyses'); assert.deepEqual(r.rows,[{attempt_id:t2}]);});
  await db.exec('reset role; set role anon;');
  await test('unauthenticated role cannot read analyses',async()=>{ await denied('select * from public.attempt_analyses');});
  console.log(`SQL security: ${passed} passed. No remote database was changed.`);
} finally { await db.close(); }
