create or replace function public.check_storage_and_alert()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_usage bigint;
  v_threshold bigint := 900 * 1024 * 1024;
  v_already_sent timestamptz;
  v_resend_key text;
begin
  v_usage := public.storage_usage_bytes();

  select alert_sent_at into v_already_sent
  from public.storage_alert_state
  where id = true;

  if v_usage < v_threshold then
    update public.storage_alert_state
    set alert_sent_at = null
    where id = true and alert_sent_at is not null;
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
      'subject', 'MistakeMap: armazenamento em 90%',
      'text', format(
        'O Supabase Storage do MistakeMap atingiu %s MB de uso (limite do plano gratuito: 1024 MB). Novos uploads serão bloqueados em 980 MB.',
        round(v_usage / 1024.0 / 1024.0)
      )
    )
  );

  update public.storage_alert_state
  set alert_sent_at = now()
  where id = true;
end;
$$;