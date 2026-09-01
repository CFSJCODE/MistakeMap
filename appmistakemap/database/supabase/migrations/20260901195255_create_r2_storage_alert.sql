-- Monitoramento de uso do Cloudflare R2: alerta por e-mail em 9 GB.
-- Diferente do Supabase Storage, o R2 é um serviço externo — não há trigger
-- nativo para bloquear uploads (isso fica para a camada que emite as URLs de
-- upload, no futuro worker/Edge Function). Este mecanismo cobre só o alerta.

create table if not exists public.r2_alert_state (
  bucket_name text primary key,
  alert_sent_at timestamptz
);

alter table public.r2_alert_state enable row level security;

create or replace function public.check_r2_storage_and_alert(
  p_bucket_name text default 'attempt-submissions'
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_account_id text := '954f3233c7c998b8e862c1a59673d9a0';
  v_cf_token text;
  v_resend_key text;
  v_request_id bigint;
  v_result net.http_response_result;
  v_body jsonb;
  v_usage bigint;
  v_threshold bigint := 9 * 1024 * 1024 * 1024;
  v_already_sent timestamptz;
  v_start text := to_char(now() - interval '2 days', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_end text := to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
begin
  select decrypted_secret into v_cf_token
  from vault.decrypted_secrets
  where name = 'cloudflare_analytics_token';

  select net.http_post(
    url := 'https://api.cloudflare.com/client/v4/graphql',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_cf_token,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'query', format(
        'query { viewer { accounts(filter: {accountTag: "%s"}) { r2StorageAdaptiveGroups(limit: 1, filter: {bucketName: "%s", datetime_geq: "%s", datetime_leq: "%s"}, orderBy: [datetime_DESC]) { max { payloadSize } } } } }',
        v_account_id, p_bucket_name, v_start, v_end
      )
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  v_result := net.http_collect_response(v_request_id, async := false);

  if v_result.status <> 'SUCCESS' then
    raise warning 'r2 analytics request failed: %', v_result.message;
    return;
  end if;

  v_body := v_result.response.body::jsonb;
  v_usage := coalesce(
    (v_body #>> '{data,viewer,accounts,0,r2StorageAdaptiveGroups,0,max,payloadSize}')::bigint,
    0
  );

  select alert_sent_at into v_already_sent
  from public.r2_alert_state
  where bucket_name = p_bucket_name;

  if not found then
    insert into public.r2_alert_state (bucket_name) values (p_bucket_name);
    v_already_sent := null;
  end if;

  if v_usage < v_threshold then
    update public.r2_alert_state
    set alert_sent_at = null
    where bucket_name = p_bucket_name and alert_sent_at is not null;
    return;
  end if;

  if v_already_sent is not null then
    return;
  end if;

  select decrypted_secret into v_resend_key
  from vault.decrypted_secrets
  where name = 'resend_api_key';

  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_resend_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'from', 'MistakeMap <onboarding@resend.dev>',
      'to', array['claudiofranciscojunior2006@gmail.com'],
      'subject', 'MistakeMap: Cloudflare R2 em 90% (' || p_bucket_name || ')',
      'text', format(
        'O bucket %s no Cloudflare R2 atingiu %s GB de uso (limite do plano gratuito: 10 GB).',
        p_bucket_name, round(v_usage / 1024.0 / 1024.0 / 1024.0, 2)
      )
    )
  );

  update public.r2_alert_state
  set alert_sent_at = now()
  where bucket_name = p_bucket_name;
end;
$$;

select cron.schedule(
  'check-r2-storage-usage',
  '*/15 * * * *',
  $$select public.check_r2_storage_and_alert('attempt-submissions');$$
);
