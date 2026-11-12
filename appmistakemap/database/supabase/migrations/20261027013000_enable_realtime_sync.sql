-- Realtime para o cache offline do app (lib/sync/).
-- O app guarda no SQLite a última resposta do Supabase e recarrega quando
-- estas tabelas mudam, por exemplo quando a IA conclui uma análise.
-- O Realtime aplica a RLS de cada tabela aos eventos de INSERT e UPDATE, então
-- cada aluno só recebe as próprias linhas; o app não assina DELETE.
-- Idempotente: só adiciona a tabela que ainda não estiver na publicação.
do $$
declare
  tabela text;
begin
  foreach tabela in array array['subjects', 'attempts', 'attempt_analyses'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = tabela
    ) then
      execute format('alter publication supabase_realtime add table public.%I', tabela);
    end if;
  end loop;
end
$$;
