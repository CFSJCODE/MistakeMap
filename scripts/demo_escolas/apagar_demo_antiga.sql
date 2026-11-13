-- Apaga as contas e escolas de demonstração antigas antes de recriar tudo
-- (pedido do dono em 2026-11-13: "todas, menos a minha e a do Lucas").
--
-- * Mantém só as contas listadas em v_manter (o dono e o coautor).
-- * Apaga as escolas marcadas como demonstração (school_billing_settings.demo).
-- * Mantém a escola de TESTE REAL de cobrança (sem a marca demo): ela perde o
--   dono antigo e é devolvida ao novo dono da Oficina Volt em seed_escolas.sql.
-- A exclusão em auth.users leva em cascata perfil, tentativas, análises,
-- caderno, papéis e turmas de cada conta.
begin;

do $$
declare
  -- Ids (não e-mails, para não publicar dado pessoal): dono e coautor.
  v_manter constant uuid[] := array[
    '1518df42-e1de-4094-a313-02d319f79aa3',
    '887633fb-5f78-4e92-9778-d744e24d22fd']::uuid[];
  v_escolas integer;
  v_contas integer;
begin
  if (select count(*) from auth.users where id = any(v_manter)) <> cardinality(v_manter) then
    raise exception 'conta a manter não encontrada; nada foi apagado';
  end if;

  delete from public.schools s
   using public.school_billing_settings b
   where b.school_id = s.id and b.demo;
  get diagnostics v_escolas = row_count;

  delete from auth.users where id <> all(v_manter);
  get diagnostics v_contas = row_count;

  raise notice 'apagadas: % escolas demo, % contas', v_escolas, v_contas;
end
$$;

commit;
