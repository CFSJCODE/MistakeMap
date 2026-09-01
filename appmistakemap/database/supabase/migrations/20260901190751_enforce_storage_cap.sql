create or replace function public.enforce_storage_cap()
returns trigger
language plpgsql
as $$
declare
  v_cap bigint := 980 * 1024 * 1024;
begin
  if public.storage_usage_bytes() + coalesce((new.metadata->>'size')::bigint, 0) > v_cap then
    raise exception 'storage cap exceeded: limite de 980 MB atingido'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger enforce_storage_cap
  before insert on storage.objects
  for each row execute function public.enforce_storage_cap();