create or replace function public.storage_usage_bytes()
returns bigint
language sql
stable
as $$
  select coalesce(sum((metadata->>'size')::bigint), 0)
  from storage.objects;
$$;