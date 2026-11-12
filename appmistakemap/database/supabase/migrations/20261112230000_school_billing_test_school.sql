-- Cobrança de teste de R$ 5 e escola de TESTE REAL de cobrança, pedida pelo Cláudio em 2026-11-12.
--
-- As duas escolas demo nunca geram cobrança (school_billing_settings.demo).
-- Para provar o fluxo Asaas de ponta a ponta (Pix gerado, webhook de
-- pagamento/cancelamento, NFS-e), esta escola é REAL: sem a marca demo, com o
-- CNPJ informado pelo dono do produto e dono = dono.demo@mistakemap.dev.
-- Ela nasce no plano grátis; o plano e a forma de pagamento são escolhidos na
-- tela de Cobrança do app, como em qualquer escola.
--
-- Usa public.create_school (o mesmo caminho do app) com a identidade do dono,
-- para respeitar o limite de escolas e gravar o papel 'owner'. Idempotente: se
-- a conta não existir ou a escola/CNPJ já existir, não faz nada.

-- Cobrança de teste (R$ 5, sem plano): kind = 'test'. Paga, não muda o plano
-- (school_invoice_paid só mexe no plano em 'checkout'), não gera NFS-e e não
-- vira crédito no fechamento do mês (que só soma 'checkout').
alter table public.school_invoices drop constraint school_invoices_kind_check;
alter table public.school_invoices add constraint school_invoices_kind_check
  check (kind in ('checkout','monthly','test'));

do $$
declare
  v_owner uuid;
begin
  select id into v_owner from auth.users where email = 'dono.demo@mistakemap.dev';
  if v_owner is null
     or exists (select 1 from public.schools where cnpj = '54497959000103') then
    return;
  end if;

  -- auth.uid() lê request.jwt.claim.sub ou request.jwt.claims->>'sub'.
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  perform public.create_school('Escola Teste de Cobrança (real)', '54497959000103');
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;
