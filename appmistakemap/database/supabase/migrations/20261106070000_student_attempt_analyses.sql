-- A análise original é evidência imutável do que a IA sugeriu. A leitura do
-- aluno incorpora decisões posteriores sem reescrever esse diagnóstico bruto.
create view public.student_attempt_analyses
with (security_invoker = true, security_barrier = true) as
select aa.attempt_id,aa.user_id,aa.subject_id,
  jsonb_set(aa.analysis,'{errors}',coalesce(effective.errors,'[]'::jsonb),true)
    || jsonb_build_object('diagnostic_status',case
      when effective.confirmed_count>0 and effective.pending_count>0 then 'mixed'
      when effective.confirmed_count>0 then 'confirmed'
      when effective.pending_count>0 then 'suggested'
      when effective.dismissed_count>0 then 'dismissed'
      else 'no_error_events' end) as analysis,
  aa.model,aa.pipeline_version,aa.created_at
from public.attempt_analyses aa
left join lateral (
  select jsonb_agg(jsonb_build_object(
      'id',ee.id,'status',ee.status,'category',et.name,'concept',c.name,
      'evidence',coalesce(ee.evidence_ref,''),'confidence',ee.confidence)
      order by ee.created_at,ee.id) filter(where ee.status in ('pending','confirmed')) as errors,
    count(*) filter(where ee.status='pending') as pending_count,
    count(*) filter(where ee.status='confirmed') as confirmed_count,
    count(*) filter(where ee.status in ('rejected','superseded')) as dismissed_count
  from public.error_events ee
  join public.attempts a on a.id=ee.attempt_id and a.user_id=aa.user_id
  join public.concepts c on c.id=ee.concept_id and c.subject_id=aa.subject_id
  join public.error_types et on et.id=ee.error_type_id
  where ee.attempt_id=aa.attempt_id
) effective on true
where aa.user_id=(select auth.uid());

revoke all on public.student_attempt_analyses from public,anon,authenticated;
grant select on public.student_attempt_analyses to authenticated;
comment on view public.student_attempt_analyses is 'Leitura do aluno com RLS do invocador. Sugestões pendentes são hipóteses; rejeitadas/superadas saem do mapa. JSON original em attempt_analyses é preservado.';
