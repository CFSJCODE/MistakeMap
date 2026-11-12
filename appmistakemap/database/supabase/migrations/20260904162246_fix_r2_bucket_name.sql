-- O bucket real do R2 é "mistakemap" (renomeado fora do fluxo de migrations,
-- direto no dashboard da Cloudflare) — não "attempt-submissions", usado nas
-- migrations anteriores. Atualiza os defaults das funções e reagenda os cron
-- jobs para apontar para o bucket correto.

create or replace function public.request_r2_storage_usage(
  p_bucket_name text default 'mistakemap'
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_account_id text := '954f3233c7c998b8e862c1a59673d9a0';
  v_cf_token text;
  v_request_id bigint;
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
        'query { viewer { accounts(filter: {accountTag: "%s"}) { r2StorageAdaptiveGroups(limit: 1, filter: {bucketName: "%s", datetime_geq: "%s", datetime_leq: "%s"}, orderBy: [datetime_DESC]) { max { payloadSize } dimensions { datetime } } } } }',
        v_account_id, p_bucket_name, v_start, v_end
      )
    ),
    timeout_milliseconds := 10000
  ) into v_request_id;

  insert into public.r2_alert_state (bucket_name, pending_request_id)
  values (p_bucket_name, v_request_id)
  on conflict (bucket_name)
    do update set pending_request_id = excluded.pending_request_id;
end;
$$;

create or replace function public.process_r2_storage_usage(
  p_bucket_name text default 'mistakemap'
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_resend_key text;
  v_request_id bigint;
  v_body jsonb;
  v_usage bigint;
  v_threshold bigint := 9::bigint * 1024 * 1024 * 1024;
  v_already_sent timestamptz;
begin
  select pending_request_id, alert_sent_at
  into v_request_id, v_already_sent
  from public.r2_alert_state
  where bucket_name = p_bucket_name;

  if v_request_id is null then
    return;
  end if;

  select content::jsonb into v_body
  from net._http_response
  where id = v_request_id and status_code = 200;

  if v_body is null then
    return;
  end if;

  v_usage := coalesce(
    (v_body #>> '{data,viewer,accounts,0,r2StorageAdaptiveGroups,0,max,payloadSize}')::bigint,
    0
  );

  update public.r2_alert_state
  set pending_request_id = null
  where bucket_name = p_bucket_name;

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

select cron.unschedule('request-r2-storage-usage');
select cron.unschedule('process-r2-storage-usage');

select cron.schedule(
  'request-r2-storage-usage',
  '*/15 * * * *',
  $$select public.request_r2_storage_usage('mistakemap');$$
);

select cron.schedule(
  'process-r2-storage-usage',
  '2-59/15 * * * *',
  $$select public.process_r2_storage_usage('mistakemap');$$
);
