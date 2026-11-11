-- Contrato e LGPD da escola (onda 1, item E do plano consolidado por perfil).
--
-- O dono aceita, com versão e data, os Termos de Uso, o Contrato SaaS e o
-- Acordo de Tratamento de Dados (escola controladora, MistakeMap operador).
-- Enquanto faltar o aceite da versão vigente de algum dos três, a escola fica
-- bloqueada: não cria nem resgata convite, não vincula turma e ninguém entra
-- em turma dela. Quem confere são triggers, então vale para qualquer caminho
-- de escrita (RPC, Edge Function com service_role ou SQL direto).
--
-- Os textos são versionados no repo em appmistakemap/database/legal/ e
-- copiados para legal_document_versions por migration (gerada com
-- scripts/legal_document_sql.py). Versão nova = migration nova com o INSERT
-- da versão nova; a partir de effective_at ela passa a ser a exigida e as
-- escolas voltam a ficar bloqueadas até o dono aceitar de novo.

create table public.legal_document_versions (
  document text not null check (document in ('termos-de-uso','contrato-saas','acordo-tratamento-dados')),
  version text not null check (version ~ '^[0-9]+\.[0-9]+$'),
  title text not null check (char_length(title) between 3 and 200),
  body text not null check (char_length(body) between 100 and 200000),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  effective_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (document, version)
);

-- O hash gravado tem de ser o do texto, e a versão publicada não muda mais.
create or replace function public.legal_document_versions_guard()
returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' or tg_op = 'DELETE' then
    raise exception 'legal_document_immutable' using errcode = 'MM403',
      hint = 'Publique uma versão nova em vez de alterar a antiga.';
  end if;
  if new.sha256 <> encode(sha256(convert_to(new.body, 'UTF8')), 'hex') then
    raise exception 'legal_document_hash_mismatch' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke all on function public.legal_document_versions_guard() from public, anon, authenticated;
create trigger legal_document_versions_guard
  before insert or update or delete on public.legal_document_versions
  for each row execute function public.legal_document_versions_guard();

create table public.school_agreements (
  id uuid primary key default gen_random_uuid(),
  -- restrict: o aceite é prova da contratação (LGPD art. 16, II e Código
  -- Civil); escola encerrada fica com status 'closed', não é apagada.
  school_id uuid not null references public.schools(id) on delete restrict,
  document text not null,
  version text not null,
  sha256 text not null,
  accepted_by uuid references auth.users(id) on delete set null,
  -- Quem aceitou em nome da escola, guardado à parte para a prova não
  -- depender da conta continuar existindo.
  signer_name text not null check (char_length(btrim(signer_name)) between 3 and 160),
  signer_role text not null check (char_length(btrim(signer_role)) between 2 and 80),
  signer_email text,
  accepted_at timestamptz not null default now(),
  ip text,
  user_agent text check (user_agent is null or char_length(user_agent) <= 400),
  foreign key (document, version) references public.legal_document_versions(document, version),
  unique (school_id, document, version)
);
create index school_agreements_school on public.school_agreements(school_id, accepted_at desc);

-- Aceite registrado não muda. A única exceção é o próprio banco limpar
-- accepted_by quando a conta de quem aceitou é excluída (on delete set null);
-- nome, cargo e e-mail de quem assinou continuam guardados.
create or replace function public.school_agreements_immutable()
returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.accepted_by is null
     and (to_jsonb(new) - 'accepted_by') = (to_jsonb(old) - 'accepted_by') then
    return new;
  end if;
  raise exception 'school_agreement_immutable' using errcode = 'MM403';
end;
$$;
revoke all on function public.school_agreements_immutable() from public, anon, authenticated;
create trigger school_agreements_immutable
  before update or delete on public.school_agreements
  for each row execute function public.school_agreements_immutable();

-- ---------------------------------------------------------------------------
-- Versão exigida e situação da escola
-- ---------------------------------------------------------------------------

-- Versão vigente de cada documento: a mais recente já em vigor.
create or replace function public.current_legal_documents()
returns table(document text, version text, title text, sha256 text, effective_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select distinct on (d.document) d.document, d.version, d.title, d.sha256, d.effective_at
  from public.legal_document_versions d
  where d.effective_at <= now()
  order by d.document, d.effective_at desc, d.created_at desc;
$$;

-- A escola tem os três documentos vigentes aceitos?
create or replace function public.school_agreements_complete(p_school uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select (select count(*) from public.current_legal_documents()) = 3
     and not exists(
       select 1 from public.current_legal_documents() c
       where not exists(select 1 from public.school_agreements a
                        where a.school_id = p_school
                          and a.document = c.document and a.version = c.version));
$$;

-- A escola pode ser usada: ativa (ou piloto) e com o contrato vigente aceito.
-- Itens seguintes (cota, cobrança, painéis, mapa da turma) devem conferir
-- esta função antes de agir em nome da escola.
create or replace function public.school_is_usable(p_school uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.schools s
                where s.id = p_school and s.status in ('pilot','active'))
     and public.school_agreements_complete(p_school);
$$;

create or replace function public.require_school_usable(p_school uuid)
returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_school is not null and not public.school_is_usable(p_school) then
    raise exception 'school_agreements_pending' using errcode = 'MM428',
      hint = 'O dono da escola precisa aceitar os termos, o contrato e o acordo de dados vigentes.';
  end if;
end;
$$;

revoke all on function public.current_legal_documents(),
  public.school_agreements_complete(uuid),
  public.school_is_usable(uuid),
  public.require_school_usable(uuid) from public, anon;
grant execute on function public.current_legal_documents(),
  public.school_agreements_complete(uuid),
  public.school_is_usable(uuid) to authenticated, service_role;
grant execute on function public.require_school_usable(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Bloqueio até o aceite (triggers: valem para qualquer caminho de escrita)
-- ---------------------------------------------------------------------------

create or replace function public.school_usable_guard()
returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_school uuid;
begin
  if tg_table_name = 'school_invites' then
    v_school := new.school_id;
  elsif tg_table_name = 'school_members' then
    -- O dono fundador entra sem convite logo ao criar a escola, antes do
    -- aceite (é ele quem aceita). Todo o resto espera o aceite.
    if new.invite_id is null then
      return new;
    end if;
    v_school := new.school_id;
  elsif tg_table_name = 'platform_classes' then
    if new.school_id is null
       or (tg_op = 'UPDATE' and new.school_id is not distinct from old.school_id) then
      return new;
    end if;
    v_school := new.school_id;
  elsif tg_table_name = 'platform_memberships' then
    select c.school_id into v_school from public.platform_classes c where c.id = new.class_id;
  end if;
  perform public.require_school_usable(v_school);
  return new;
end;
$$;
revoke all on function public.school_usable_guard() from public, anon, authenticated;

create trigger school_invites_usable_guard
  before insert on public.school_invites
  for each row execute function public.school_usable_guard();
create trigger school_members_usable_guard
  before insert on public.school_members
  for each row execute function public.school_usable_guard();
create trigger platform_classes_usable_guard
  before insert or update of school_id on public.platform_classes
  for each row execute function public.school_usable_guard();
create trigger platform_memberships_usable_guard
  before insert on public.platform_memberships
  for each row execute function public.school_usable_guard();

-- ---------------------------------------------------------------------------
-- Operações (RPC)
-- ---------------------------------------------------------------------------

-- Situação do contrato da escola, com o texto vigente de cada documento.
-- Dono e coordenador leem (matriz "Contrato, plano e fatura": coordenador vê);
-- admin do MistakeMap também.
create or replace function public.school_agreement_status(p_school uuid)
returns table(document text, version text, title text, body text, sha256 text,
              effective_at timestamptz, accepted_at timestamptz,
              signer_name text, signer_role text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if not public.is_school_member(p_school, array['owner','coordinator'])
     and not coalesce(public.is_admin(), false) then
    raise exception 'forbidden' using errcode = 'MM403';
  end if;
  return query
    select c.document, c.version, c.title, d.body, c.sha256, c.effective_at,
           a.accepted_at, a.signer_name, a.signer_role
    from public.current_legal_documents() c
    join public.legal_document_versions d on d.document = c.document and d.version = c.version
    left join public.school_agreements a
      on a.school_id = p_school and a.document = c.document and a.version = c.version
    order by array_position(array['termos-de-uso','contrato-saas','acordo-tratamento-dados'], c.document);
end;
$$;

-- O dono aceita os documentos vigentes. p_documents traz o que a tela
-- mostrou: [{"document": ..., "version": ..., "sha256": ...}]. Se o texto
-- mudou nesse meio-tempo, o aceite é recusado e a tela recarrega.
create or replace function public.accept_school_agreements(
  p_school uuid,
  p_documents jsonb,
  p_signer_name text,
  p_signer_role text)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_headers jsonb := coalesce(nullif(current_setting('request.headers', true), '')::jsonb, '{}'::jsonb);
  v_email text;
  v_ip text;
  v_doc record;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'MM401';
  end if;
  if not public.is_school_member(p_school, array['owner']) then
    raise exception 'forbidden' using errcode = 'MM403',
      hint = 'Só o dono da escola aceita o contrato.';
  end if;
  if not exists(select 1 from public.schools s where s.id = p_school and s.status <> 'closed') then
    raise exception 'school_closed' using errcode = 'MM403';
  end if;
  if jsonb_typeof(p_documents) is distinct from 'array' then
    raise exception 'invalid_documents' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_signer_name, ''))) < 3
     or char_length(btrim(coalesce(p_signer_role, ''))) < 2 then
    raise exception 'signer_required' using errcode = '22023',
      hint = 'Informe o nome completo e o cargo de quem aceita pela escola.';
  end if;

  -- Cada documento vigente precisa vir com a mesma versão e o mesmo hash.
  for v_doc in select * from public.current_legal_documents() loop
    if not exists(select 1 from jsonb_array_elements(p_documents) e
                  where e->>'document' = v_doc.document
                    and e->>'version' = v_doc.version
                    and e->>'sha256' = v_doc.sha256) then
      raise exception 'agreement_version_mismatch' using errcode = 'MM409',
        hint = 'Os textos foram atualizados. Recarregue e leia a versão vigente.';
    end if;
  end loop;

  select lower(u.email) into v_email from auth.users u where u.id = v_uid;
  v_ip := nullif(btrim(split_part(coalesce(v_headers->>'x-forwarded-for', v_headers->>'x-real-ip', ''), ',', 1)), '');

  insert into public.school_agreements(school_id, document, version, sha256, accepted_by,
                                       signer_name, signer_role, signer_email, ip, user_agent)
    select p_school, c.document, c.version, c.sha256, v_uid,
           btrim(p_signer_name), btrim(p_signer_role), v_email, left(v_ip, 64),
           left(v_headers->>'user-agent', 400)
    from public.current_legal_documents() c
  on conflict (school_id, document, version) do nothing;

  return public.school_is_usable(p_school);
end;
$$;

revoke all on function public.school_agreement_status(uuid),
  public.accept_school_agreements(uuid, jsonb, text, text) from public, anon;
grant execute on function public.school_agreement_status(uuid),
  public.accept_school_agreements(uuid, jsonb, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.legal_document_versions enable row level security;
alter table public.school_agreements enable row level security;
revoke all on public.legal_document_versions, public.school_agreements
  from public, anon, authenticated;
grant select, insert on public.legal_document_versions to service_role;
grant select, insert on public.school_agreements to service_role;

-- Os textos legais são públicos para quem está logado.
create policy legal_document_versions_read on public.legal_document_versions
  for select to authenticated using (true);
grant select on public.legal_document_versions to authenticated;

-- Aceites: dono e coordenador da escola veem; admin do MistakeMap também.
-- TI, professor, estudante e responsável não veem (matriz "Contrato").
create policy school_agreements_read on public.school_agreements
  for select to authenticated
  using (public.is_school_member(school_id, array['owner','coordinator'])
         or coalesce(public.is_admin(), false));
grant select on public.school_agreements to authenticated;

-- ---------------------------------------------------------------------------
-- Textos da versão 1.0 (appmistakemap/database/legal/*/1.0.md)
-- ---------------------------------------------------------------------------

insert into public.legal_document_versions(document, version, title, body, sha256, effective_at) values (
  'termos-de-uso', '1.0', 'Termos de Uso do MistakeMap para Escolas',
  $legal$# Termos de Uso do MistakeMap para Escolas

Versão 1.0, em vigor desde 11 de novembro de 2026.

Estes Termos regem o uso do MistakeMap por uma instituição de ensino ("Escola") e pelas pessoas que ela convida: dono, coordenação, TI, professores, estudantes e responsáveis ("Usuários"). Eles valem junto com o Contrato de Prestação de Serviços (SaaS) e com o Acordo de Tratamento de Dados Pessoais, que a Escola aceita na mesma tela. Se houver conflito, vale primeiro o Acordo de Tratamento de Dados, depois o Contrato e por último estes Termos.

## 1. O que é o MistakeMap

1.1. O MistakeMap é uma plataforma de estudo que recebe exercícios resolvidos pelo estudante, identifica com apoio de inteligência artificial os padrões de erro e organiza esses erros num mapa pessoal, num treino dirigido e num caderno de regras escrito pelo próprio estudante.

1.2. A análise feita pela inteligência artificial é um apoio pedagógico. Ela pode conter erros e não substitui a avaliação do professor. Nenhuma nota, aprovação ou decisão sobre o estudante deve ser tomada só com base nela.

## 2. Quem representa a Escola

2.1. Quem cria a escola no MistakeMap e aceita estes Termos declara que tem poderes para representar a Escola e para contratar em nome dela.

2.2. O dono da escola é o responsável pela conta da Escola. Ele pode convidar coordenadores e a equipe de TI, e estes podem convidar professores, estudantes e responsáveis, conforme as permissões descritas no aplicativo.

2.3. Cada papel só é concedido por convite validado no servidor do MistakeMap. A Escola deve enviar convites apenas a pessoas que de fato fazem parte da comunidade escolar e revogar convites e acessos de quem deixar a Escola.

## 3. Contas e acesso

3.1. Cada Usuário usa uma conta pessoal e intransferível. A senha e os códigos de convite não devem ser compartilhados.

3.2. A Escola é responsável pelas ações feitas pelas contas que ela convidou, inclusive pela exatidão dos dados de cadastro informados em planilhas de importação.

3.3. A equipe de TI administra contas, turmas e uso, mas não tem acesso a respostas, mapas de erro ou caderno dos estudantes. Professores e coordenação só veem dados individuais de um estudante com o consentimento dele ou dentro do que a Escola, como controladora, definir com base legal adequada.

## 4. Estudantes menores de idade

4.1. A Escola declara que obteve, ou obterá antes do primeiro acesso, as autorizações exigidas pela legislação para que seus estudantes menores de 18 anos usem o MistakeMap, observando o melhor interesse da criança e do adolescente (art. 14 da Lei 13.709/2018, LGPD, e Lei 15.211/2025).

4.2. O MistakeMap não exibe anúncios a escolas nem a estudantes menores de 18 anos e não usa os dados dos estudantes para publicidade, perfilamento comercial ou venda de dados.

## 5. Uso permitido

5.1. A plataforma deve ser usada para fins educacionais. É proibido:

a) enviar conteúdo ilícito, ofensivo, discriminatório ou que exponha a intimidade de terceiros;

b) enviar fotos de pessoas, documentos de identidade ou dados de saúde nos exercícios;

c) tentar acessar dados de outra escola ou de outro Usuário, contornar limites de uso, testar a segurança sem autorização por escrito ou automatizar acessos fora das interfaces oferecidas;

d) copiar, revender ou redistribuir o banco de questões e os conteúdos do MistakeMap fora da Escola.

5.2. O MistakeMap pode suspender a conta que descumprir esta cláusula, avisando a Escola e, quando possível, o próprio Usuário.

## 6. Cota de análises por inteligência artificial

6.1. Cada plano inclui uma cota de análises por mês, informada no aplicativo e na proposta comercial. Atingida a cota, novas análises dependem do plano contratado e podem ser cobradas como excedente, conforme o Contrato.

6.2. Para manter a plataforma estável, o MistakeMap pode limitar envios em sequência muito rápida, sem que isso caracterize falha do serviço.

## 7. Propriedade intelectual

7.1. O software, a marca, o banco de questões e os textos do MistakeMap pertencem ao MistakeMap.

7.2. Os exercícios, respostas e anotações enviados pelos Usuários continuam pertencendo a quem os criou ou à Escola. O MistakeMap os trata apenas para prestar o serviço, nos termos do Acordo de Tratamento de Dados.

## 8. Disponibilidade e mudanças

8.1. O MistakeMap busca manter a plataforma disponível de forma contínua, mas pode haver interrupções para manutenção, atualização ou por falhas de fornecedores de infraestrutura.

8.2. Estes Termos podem ser atualizados. A nova versão é mostrada ao dono da escola no aplicativo, com a data e o número da versão, e o uso da escola fica bloqueado até o novo aceite. Mudanças que reduzam direitos dos titulares de dados também seguem o Acordo de Tratamento de Dados.

## 9. Contato

Dúvidas sobre estes Termos e pedidos ligados a dados pessoais podem ser enviados pelo canal de suporte e privacidade indicado na página Sobre do aplicativo.
$legal$,
  'ebe39d52f5950eb392009938a54bc6a32d57891fcfd76d370c0741ab2bd1733f', '2026-11-11T00:00:00-03:00');

insert into public.legal_document_versions(document, version, title, body, sha256, effective_at) values (
  'contrato-saas', '1.0', 'Contrato de Prestação de Serviços do MistakeMap (SaaS)',
  $legal$# Contrato de Prestação de Serviços do MistakeMap (SaaS)

Versão 1.0, em vigor desde 11 de novembro de 2026.

De um lado, a instituição de ensino identificada no cadastro da escola no MistakeMap, representada pela pessoa que aceita este Contrato ("CONTRATANTE" ou "Escola"). De outro, o MistakeMap, cujos dados de identificação (razão social, CNPJ e endereço) constam na proposta comercial e em cada nota fiscal emitida ("CONTRATADA").

As partes celebram este Contrato, que integra os Termos de Uso para Escolas e o Acordo de Tratamento de Dados Pessoais aceitos na mesma ocasião.

## 1. Objeto

1.1. A CONTRATADA concede à Escola, enquanto este Contrato estiver vigente, o direito de uso, não exclusivo e intransferível, da plataforma MistakeMap no modelo de software como serviço, pelos aplicativos para Android, Windows e navegador.

1.2. Estão incluídos: hospedagem, atualizações, análise de erros por inteligência artificial dentro da cota do plano, mapa de erros, treino dirigido, banco de questões, turmas, painéis de gestão e suporte por canal digital.

## 2. Planos e preço

2.1. O plano, o preço por aluno ativo, a cota de análises, o valor do excedente, o valor mínimo mensal e os descontos por volume são os da proposta comercial aceita pela Escola ou, na falta dela, os da tabela vigente mostrada no aplicativo no momento da contratação.

2.2. Aluno ativo é o estudante vinculado à Escola que usou o MistakeMap ao menos uma vez no mês de referência. Professores, coordenação, TI e responsáveis não são cobrados.

2.3. O plano Grátis não gera cobrança e tem os limites de usuários, turmas e análises mostrados no aplicativo.

2.4. Os preços podem ser reajustados uma vez a cada 12 meses pela variação do IPCA, ou por outro índice oficial que o substitua, com aviso de 30 dias.

## 3. Faturamento e pagamento

3.1. No primeiro dia de cada mês, a CONTRATADA apura os alunos ativos e as análises excedentes do mês anterior e emite a cobrança, com a nota fiscal correspondente.

3.2. O pagamento é feito por Pix ou boleto, no prazo indicado na cobrança. Nos planos anuais, o valor e a forma de pagamento seguem a proposta comercial.

3.3. Em caso de atraso, incidem multa de 2% e juros de 1% ao mês, proporcionais aos dias de atraso. Depois de 15 dias de atraso e de aviso ao dono da escola, a CONTRATADA pode suspender o acesso da Escola até a regularização, sem apagar os dados.

## 4. Obrigações da CONTRATADA

4.1. Prestar o serviço com diligência, mantendo medidas de segurança técnicas e administrativas adequadas, descritas no Acordo de Tratamento de Dados.

4.2. Buscar disponibilidade mensal de 99% da plataforma, desconsideradas as manutenções programadas avisadas com 48 horas de antecedência e as falhas causadas por terceiros fora do controle razoável da CONTRATADA.

4.3. Responder aos chamados de suporte em até 2 dias úteis.

4.4. Não exibir anúncios a Usuários da Escola e não usar os dados da Escola ou dos estudantes para publicidade, venda de dados ou treinamento de modelos de inteligência artificial.

## 5. Obrigações da Escola

5.1. Manter corretos os dados de cadastro, de cobrança e de contato do dono da escola.

5.2. Convidar apenas membros da comunidade escolar, gerir os acessos e cumprir os Termos de Uso.

5.3. Como controladora dos dados pessoais, definir a base legal dos tratamentos, informar os titulares e obter as autorizações exigidas, inclusive as de responsáveis por estudantes menores de idade.

5.4. Pagar os valores devidos nos prazos.

## 6. Vigência e encerramento

6.1. Este Contrato vale por prazo indeterminado nos planos mensais e pelo período contratado nos planos anuais, renovando-se automaticamente por igual período se nenhuma das partes se manifestar com 30 dias de antecedência.

6.2. Qualquer das partes pode encerrar o plano mensal com aviso de 30 dias. O plano anual pode ser encerrado antes do fim, sendo devido o valor proporcional ao período usado com o desconto do plano mensal.

6.3. A CONTRATADA pode encerrar o Contrato de imediato em caso de uso ilícito da plataforma pela Escola ou de violação grave dos Termos de Uso.

6.4. Encerrado o Contrato, a Escola tem 30 dias para exportar os dados. Depois desse prazo, os dados são eliminados conforme o Acordo de Tratamento de Dados, ressalvado o que a lei obrigar a manter.

## 7. Responsabilidade

7.1. A análise por inteligência artificial é um apoio pedagógico e pode conter imprecisões. A Escola e os professores continuam responsáveis pelas decisões pedagógicas.

7.2. Salvo dolo, culpa grave ou violação do Acordo de Tratamento de Dados, a responsabilidade total de cada parte por este Contrato fica limitada ao valor pago pela Escola nos 12 meses anteriores ao fato.

7.3. Nenhuma das partes responde por lucros cessantes ou por falhas causadas por caso fortuito ou força maior.

## 8. Propriedade intelectual e confidencialidade

8.1. O software, a marca e os conteúdos do MistakeMap pertencem à CONTRATADA. Os dados e conteúdos enviados pela Escola e pelos seus Usuários pertencem a eles.

8.2. As partes mantêm em sigilo as informações não públicas da outra parte a que tiverem acesso, durante o Contrato e por 5 anos depois dele.

## 9. Disposições gerais

9.1. Este Contrato é aceito eletronicamente no aplicativo, com registro da versão, da data e hora, da conta e do nome e cargo de quem aceitou, o que as partes reconhecem como prova válida da contratação.

9.2. Novas versões deste Contrato são mostradas ao dono da escola no aplicativo e passam a valer com o aceite. Até o aceite, o uso da escola fica bloqueado.

9.3. A tolerância de uma parte com o descumprimento da outra não altera o Contrato.

9.4. Fica eleito o foro do domicílio da CONTRATANTE para resolver questões deste Contrato.
$legal$,
  '4b85f917b9b311d612424fb71f0145219b956d8952e3ed082ed01bb8d95984fd', '2026-11-11T00:00:00-03:00');

insert into public.legal_document_versions(document, version, title, body, sha256, effective_at) values (
  'acordo-tratamento-dados', '1.0', 'Acordo de Tratamento de Dados Pessoais do MistakeMap',
  $legal$# Acordo de Tratamento de Dados Pessoais do MistakeMap

Versão 1.0, em vigor desde 11 de novembro de 2026.

Este Acordo integra o Contrato de Prestação de Serviços (SaaS) e os Termos de Uso para Escolas e regula o tratamento de dados pessoais feito pelo MistakeMap em nome da Escola, nos termos da Lei 13.709/2018 (Lei Geral de Proteção de Dados Pessoais, LGPD).

## 1. Papéis das partes

1.1. A Escola é a **controladora** dos dados pessoais da sua comunidade escolar tratados na plataforma: é ela quem decide para que e como esses dados são usados.

1.2. O MistakeMap é o **operador**: trata os dados apenas em nome da Escola, conforme as instruções deste Acordo, do Contrato e das configurações que a Escola fizer no aplicativo, que valem como instruções documentadas.

1.3. Se o MistakeMap receber uma instrução que considere contrária à LGPD, avisará a Escola e poderá suspender o tratamento ligado a ela até que a questão seja resolvida.

1.4. Para dados de cobrança da própria Escola e para a segurança e melhoria técnica da plataforma, o MistakeMap atua como controlador, sem usar dados pedagógicos de estudantes para essas finalidades.

## 2. Finalidade do tratamento

2.1. O MistakeMap trata os dados exclusivamente para:

a) criar e manter as contas, papéis, turmas e convites da Escola;

b) receber exercícios, identificar padrões de erro com apoio de inteligência artificial e mostrar o mapa de erros, o treino dirigido e o caderno de regras ao estudante;

c) mostrar a professores e coordenação os dados que a Escola e o estudante autorizarem, e relatórios agregados de turma com 5 ou mais estudantes;

d) medir o uso para apurar a cota e a cobrança da Escola;

e) cumprir obrigações legais e atender pedidos dos titulares encaminhados pela Escola.

2.2. É proibido ao MistakeMap usar os dados para publicidade, perfilamento comercial, venda ou compartilhamento com fins comerciais, ou para treinar modelos de inteligência artificial próprios ou de terceiros.

## 3. Titulares e categorias de dados

As categorias de titulares, de dados e as operações estão no Anexo I. A Escola se compromete a não enviar dados pessoais sensíveis (como saúde, biometria, religião ou origem racial) e a orientar os Usuários a não incluir fotos de pessoas nem documentos nos exercícios.

## 4. Crianças e adolescentes

4.1. Os dados de estudantes menores de 18 anos são tratados no melhor interesse deles (art. 14 da LGPD e Lei 15.211/2025). Cabe à Escola, como controladora, obter o consentimento específico de um dos pais ou responsável quando essa for a base legal aplicável.

4.2. O MistakeMap não exibe anúncios a esses estudantes, não usa técnicas de engajamento compulsivo, não cria perfis para fins comerciais e coleta apenas os dados necessários para a atividade pedagógica.

## 5. Inteligência artificial e decisões automatizadas

5.1. As análises de erro são geradas por provedores de inteligência artificial listados no Anexo II, contratados em condições que proíbem o uso dos dados enviados para treinar seus modelos.

5.2. O MistakeMap envia a esses provedores apenas o conteúdo do exercício e da resposta, sem nome, e-mail ou outro identificador direto do estudante.

5.3. A análise é uma sugestão pedagógica. Nenhuma decisão que afete os interesses do estudante é tomada só com base nela, e o estudante ou o responsável pode pedir revisão por pessoa natural (art. 20 da LGPD), encaminhada pela Escola.

## 6. Confidencialidade e controle de acesso

6.1. Todas as pessoas autorizadas pelo MistakeMap a tratar os dados estão sujeitas a dever de sigilo.

6.2. O acesso dentro da plataforma segue o menor privilégio: a TI da Escola administra contas e uso, mas não vê respostas, mapas de erro ou caderno; professores e coordenação só veem dados individuais com o consentimento do estudante ou conforme a base legal definida pela Escola; o suporte do MistakeMap não acessa dados pedagógicos dos estudantes.

## 7. Segurança

O MistakeMap mantém as medidas técnicas e administrativas do Anexo III e as revisa sempre que houver mudança relevante na plataforma.

## 8. Suboperadores

8.1. A Escola autoriza o uso dos suboperadores do Anexo II. O MistakeMap exige de cada um obrigações de proteção de dados equivalentes às deste Acordo e responde perante a Escola pelo descumprimento delas.

8.2. A inclusão ou troca de suboperador é avisada ao dono da escola com pelo menos 15 dias de antecedência. A Escola pode se opor por motivo razoável ligado à proteção de dados; se não houver solução, pode encerrar o Contrato sem multa.

## 9. Transferência internacional

Parte dos suboperadores processa dados fora do Brasil. Essas transferências seguem o art. 33 da LGPD, com base nas cláusulas-padrão contratuais aprovadas pela ANPD (Resolução CD/ANPD nº 19/2024) ou em outro mecanismo válido.

## 10. Direitos dos titulares

10.1. A plataforma permite que o próprio Usuário exporte e exclua a sua conta. Os demais pedidos (confirmação, acesso, correção, anonimização, portabilidade, informação sobre compartilhamento, revisão de decisão automatizada e revogação de consentimento) chegam pela Escola ou são encaminhados a ela.

10.2. O MistakeMap ajuda a Escola a responder aos titulares no prazo legal, executando as medidas técnicas necessárias em até 10 dias contados do pedido da Escola.

## 11. Incidentes de segurança

11.1. O MistakeMap comunica à Escola, em até 48 horas depois de tomar conhecimento, qualquer incidente de segurança que possa acarretar risco ou dano relevante aos titulares, informando a natureza dos dados afetados, os titulares envolvidos, as medidas adotadas e o contato para acompanhamento.

11.2. O MistakeMap apoia a Escola na comunicação à ANPD e aos titulares, que a controladora deve fazer em até 3 dias úteis (Resolução CD/ANPD nº 15/2024), e registra o incidente.

## 12. Retenção e eliminação

12.1. Os dados ficam guardados enquanto a conta do Usuário ou o Contrato estiver vigente.

12.2. Encerrado o Contrato, a Escola tem 30 dias para exportar os dados. Em seguida, o MistakeMap elimina os dados em até 30 dias, e as cópias de segurança são sobrescritas em até mais 30 dias.

12.3. Podem ser mantidos apenas os dados que a lei obrigar, como os registros de acesso pelo prazo do Marco Civil da Internet, os dados de cobrança pelo prazo fiscal e o registro deste aceite como prova da contratação.

## 13. Auditoria

13.1. Uma vez por ano, ou depois de um incidente, a Escola pode pedir informações sobre o cumprimento deste Acordo, que o MistakeMap responde por escrito em até 30 dias.

13.2. Auditorias presenciais ou técnicas dependem de agendamento, sigilo e não podem expor dados de outras escolas.

## 14. Responsabilidade e vigência

14.1. Cada parte responde pelos danos que causar por violação da LGPD, nos termos dos arts. 42 a 45, sem o limite de valor do Contrato.

14.2. Este Acordo vale enquanto houver tratamento de dados da Escola pelo MistakeMap, mesmo depois do fim do Contrato.

14.3. Novas versões deste Acordo são mostradas ao dono da escola no aplicativo e passam a valer com o aceite; até lá, o uso da escola fica bloqueado.

## 15. Encarregado

O canal do encarregado pelo tratamento de dados pessoais do MistakeMap está indicado na página Sobre do aplicativo. A Escola deve informar ao MistakeMap o contato do seu próprio encarregado.

---

## Anexo I. Descrição do tratamento

| Titulares | Dados | Operações |
| --- | --- | --- |
| Estudantes, inclusive menores de 18 anos | nome, e-mail, data de nascimento, escola, turma, equipe; exercícios, imagens dos exercícios, respostas, análises de erro, mapa de erros, treinos, caderno de regras, consentimentos de compartilhamento | coleta, armazenamento, análise por IA, exibição ao próprio estudante e aos autorizados, agregação por turma, exportação, eliminação |
| Professores e coordenação | nome, e-mail, papel, turmas, tarefas criadas, comentários | armazenamento, exibição, auditoria |
| TI e dono da escola | nome, e-mail, papel, ações administrativas, aceites deste Acordo | armazenamento, auditoria |
| Pais e responsáveis | nome, e-mail, vínculo com o estudante, consentimento | armazenamento, comprovação do consentimento |
| Todos os Usuários | endereço IP, aparelho, versão do aplicativo, data e hora de acesso | registros de segurança e de acesso |

## Anexo II. Suboperadores

| Suboperador | Finalidade | Local |
| --- | --- | --- |
| Supabase | banco de dados, autenticação e funções do servidor | região da hospedagem do projeto, podendo envolver os Estados Unidos |
| Cloudflare (R2) | armazenamento das imagens dos exercícios | Estados Unidos e outros países da rede Cloudflare |
| Google (API Gemini) | análise de erros e geração de treinos por IA | Estados Unidos e outros países do Google |
| Anthropic (API Claude) | análise de erros por IA no plano Plus | Estados Unidos |
| OpenRouter | rota de reserva para a análise por IA, quando o provedor principal estiver indisponível | Estados Unidos |
| Vercel | hospedagem da versão web do aplicativo | Estados Unidos e outros países |
| Asaas | cobrança da Escola por Pix e boleto e emissão de nota fiscal (somente dados da Escola contratante) | Brasil |

## Anexo III. Medidas de segurança

1. Conexões criptografadas (HTTPS/TLS) entre o aplicativo, o servidor e os suboperadores.
2. Controle de acesso por linha no banco de dados (Row Level Security) em todas as tabelas com dados de Usuários, conferido no servidor e não só na tela.
3. Papéis da escola concedidos apenas por convite validado no servidor; códigos de convite guardados somente como hash.
4. Chaves de serviço e segredos guardados fora do aplicativo, em cofre do servidor.
5. Separação entre dados administrativos e pedagógicos, de modo que a TI da Escola e o suporte não acessem dados pedagógicos dos estudantes.
6. Relatórios de turma apenas agregados e com 5 ou mais estudantes.
7. Envio aos provedores de IA sem identificadores diretos do estudante.
8. Cópias de segurança periódicas e procedimento de resposta a incidentes.
9. Registro de auditoria das ações administrativas e dos aceites deste Acordo.
$legal$,
  '55a1237a1522f672815c65bd78128f6ec4a6b18a5985c501b8e588fd70d1e577', '2026-11-11T00:00:00-03:00');

