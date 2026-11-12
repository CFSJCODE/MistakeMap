-- Catálogo de exercícios revisados: cinco por matéria/assunto/tema.
--
-- O catálogo é global e só de leitura para o app. O gabarito fica numa tabela
-- sem acesso do cliente (como practice_answer_keys): a resposta só aparece na
-- correção. Integração: o generate-practice serve primeiro exercícios do
-- catálogo cujo tema é um dos conceitos com erro do aluno (ou, sem erros, da
-- mesma matéria) e só chama a IA quando o catálogo não cobre a rodada. O
-- exercício copiado para o aluno guarda catalog_exercise_id, e o gabarito
-- revisado vira a referência da análise.
--
-- O bloco de conteúdo é idempotente (upsert pela chave matéria, assunto, tema
-- e posição): para revisar uma questão, copie-o para uma migration nova.

create table public.catalog_exercises (
  id uuid primary key default gen_random_uuid(),
  subject text not null check (char_length(btrim(subject)) between 1 and 120),
  topic text not null check (char_length(btrim(topic)) between 1 and 120),
  theme text not null check (char_length(btrim(theme)) between 1 and 120),
  position smallint not null check (position between 1 and 5),
  difficulty text not null check (difficulty in ('facil', 'media', 'dificil')),
  prompt_text text not null check (char_length(btrim(prompt_text)) > 0),
  -- Tipo de erro que o exercício treina (mesma taxonomia da análise).
  error_category text not null references public.error_types(name),
  reviewed_at timestamptz not null,
  reviewed_by text not null,
  unique (subject, topic, theme, position)
);

create index catalog_exercises_theme_idx on public.catalog_exercises (lower(theme));
create index catalog_exercises_subject_idx on public.catalog_exercises (lower(subject));

create table public.catalog_answer_keys (
  catalog_exercise_id uuid primary key
    references public.catalog_exercises(id) on delete cascade,
  correct_answer text not null,
  explanation text not null
);

alter table public.catalog_exercises enable row level security;
alter table public.catalog_answer_keys enable row level security;

create policy catalog_exercises_read on public.catalog_exercises
  for select to authenticated using (true);

revoke all on public.catalog_exercises from public, anon, authenticated;
grant select on public.catalog_exercises to authenticated;
grant all on public.catalog_exercises to service_role;

-- Sem política nem grant para o cliente: o gabarito só sai pela correção.
revoke all on public.catalog_answer_keys from public, anon, authenticated;
grant all on public.catalog_answer_keys to service_role;

-- Exercício do aluno que veio do catálogo (nulo para os demais).
alter table public.exercises
  add column catalog_exercise_id uuid
    references public.catalog_exercises(id) on delete set null;

create index exercises_catalog_idx on public.exercises (catalog_exercise_id)
  where catalog_exercise_id is not null;

-- ─── Conteúdo revisado ──────────────────────────────────────────────────────
-- Cada linha: [matéria, assunto, tema, posição, dificuldade, tipo de erro,
-- enunciado, gabarito, explicação]. Cada questão foi resolvida para conferir
-- o gabarito antes de entrar aqui.
do $catalogo$
declare
  item jsonb;
  cid uuid;
  revisao constant timestamptz := '2026-11-02T00:00:00Z';
  itens constant jsonb := $json$
  [
    ["Matemática", "Álgebra", "Equação do 1º grau", 1, "facil", "calculo",
     "Resolva a equação 4x + 3 = 19.",
     "x = 4",
     "4x = 19 - 3 = 16, logo x = 16 ÷ 4 = 4."],
    ["Matemática", "Álgebra", "Equação do 1º grau", 2, "facil", "sinal",
     "Resolva a equação 5 - 2x = 11.",
     "x = -3",
     "-2x = 11 - 5 = 6, logo x = 6 ÷ (-2) = -3. O sinal de menos acompanha o 2x."],
    ["Matemática", "Álgebra", "Equação do 1º grau", 3, "media", "procedimento",
     "Resolva a equação 3(x - 2) = 2x + 5.",
     "x = 11",
     "Distribuindo: 3x - 6 = 2x + 5. Então 3x - 2x = 5 + 6, logo x = 11."],
    ["Matemática", "Álgebra", "Equação do 1º grau", 4, "media", "procedimento",
     "Resolva a equação x/2 + x/3 = 10.",
     "x = 12",
     "Com denominador comum 6: (3x + 2x)/6 = 10, logo 5x = 60 e x = 12."],
    ["Matemática", "Álgebra", "Equação do 1º grau", 5, "media", "interpretacao",
     "A soma de três números inteiros consecutivos é 72. Quais são esses números?",
     "23, 24 e 25",
     "Sendo x o menor: x + (x + 1) + (x + 2) = 72, logo 3x + 3 = 72, 3x = 69 e x = 23."],

    ["Matemática", "Matemática financeira", "Porcentagem", 1, "facil", "calculo",
     "Quanto é 15% de R$ 240,00?",
     "R$ 36,00",
     "15% = 0,15; 0,15 × 240 = 36."],
    ["Matemática", "Matemática financeira", "Porcentagem", 2, "media", "conceito",
     "Um produto custava R$ 80,00 e passou a custar R$ 92,00. Qual foi o aumento percentual?",
     "15%",
     "O aumento foi de R$ 12,00 sobre o preço antigo: 12 ÷ 80 = 0,15 = 15%. A base é o valor inicial."],
    ["Matemática", "Matemática financeira", "Porcentagem", 3, "media", "conceito",
     "Depois de um desconto de 25%, uma camiseta passou a custar R$ 60,00. Qual era o preço original?",
     "R$ 80,00",
     "Pagar 75% do preço dá R$ 60,00: preço = 60 ÷ 0,75 = 80. Somar 25% sobre 60 daria 75, que está errado."],
    ["Matemática", "Matemática financeira", "Porcentagem", 4, "media", "conceito",
     "Dois descontos sucessivos de 10% e de 20% equivalem a qual desconto único?",
     "28%",
     "Os fatores se multiplicam: 0,90 × 0,80 = 0,72. Paga-se 72% do preço, ou seja, desconto de 28%, e não de 30%."],
    ["Matemática", "Matemática financeira", "Porcentagem", 5, "dificil", "conceito",
     "Uma ação caiu 20% em um mês. Quanto ela precisa subir no mês seguinte para voltar ao valor inicial?",
     "25%",
     "Depois da queda vale 0,8 do inicial. Para voltar a 1: 1 ÷ 0,8 = 1,25, ou seja, alta de 25% sobre o valor já reduzido."],

    ["Física", "Dinâmica", "Segunda lei de Newton", 1, "facil", "conceito",
     "Uma força resultante de 30 N age sobre um corpo de 6 kg. Qual é a aceleração do corpo?",
     "5 m/s²",
     "F = m · a, logo a = F ÷ m = 30 ÷ 6 = 5 m/s²."],
    ["Física", "Dinâmica", "Segunda lei de Newton", 2, "facil", "calculo",
     "Qual força resultante é necessária para acelerar um carro de 1.200 kg a 2 m/s²?",
     "2.400 N",
     "F = m · a = 1.200 × 2 = 2.400 N."],
    ["Física", "Dinâmica", "Segunda lei de Newton", 3, "media", "interpretacao",
     "Um bloco de 5 kg é puxado por uma força de 40 N sobre um piso que exerce atrito de 15 N. Qual é a aceleração do bloco?",
     "5 m/s²",
     "A resultante desconta o atrito: 40 - 15 = 25 N. Então a = 25 ÷ 5 = 5 m/s²."],
    ["Física", "Dinâmica", "Segunda lei de Newton", 4, "media", "sinal",
     "Um corpo de 2 kg recebe duas forças horizontais opostas, de 18 N e de 10 N. Qual é a aceleração e em que sentido?",
     "4 m/s², no sentido da força de 18 N",
     "Forças opostas se subtraem: 18 - 10 = 8 N no sentido da maior. a = 8 ÷ 2 = 4 m/s²."],
    ["Física", "Dinâmica", "Segunda lei de Newton", 5, "dificil", "procedimento",
     "Um elevador de 500 kg sobe com aceleração constante de 2 m/s². Considerando g = 10 m/s², qual é a tração no cabo?",
     "6.000 N",
     "Para cima: T - P = m · a. Com P = 500 × 10 = 5.000 N, T = 5.000 + 500 × 2 = 6.000 N."],

    ["Física", "Cinemática", "MRUV", 1, "facil", "calculo",
     "Um carro parte do repouso com aceleração constante de 3 m/s². Qual é a velocidade dele após 4 s?",
     "12 m/s",
     "v = v0 + a · t = 0 + 3 × 4 = 12 m/s."],
    ["Física", "Cinemática", "MRUV", 2, "media", "procedimento",
     "Um móvel parte do repouso com aceleração constante de 4 m/s². Que distância ele percorre em 3 s?",
     "18 m",
     "d = v0 · t + a · t²/2 = 0 + 4 × 9 ÷ 2 = 18 m. O tempo entra ao quadrado e o termo é dividido por 2."],
    ["Física", "Cinemática", "MRUV", 3, "media", "sinal",
     "Um carro a 20 m/s freia com desaceleração constante de 5 m/s². Em quanto tempo ele para?",
     "4 s",
     "Na frenagem a aceleração é negativa: 0 = 20 - 5 · t, logo t = 4 s."],
    ["Física", "Cinemática", "MRUV", 4, "media", "procedimento",
     "Um carro a 20 m/s freia com desaceleração constante de 5 m/s² até parar. Qual é a distância de frenagem?",
     "40 m",
     "Torricelli: v² = v0² - 2 · a · d, então 0 = 400 - 10 · d e d = 40 m."],
    ["Física", "Cinemática", "MRUV", 5, "dificil", "unidade",
     "Uma moto a 36 km/h acelera a 2 m/s² durante 5 s. Qual é a velocidade final em m/s?",
     "20 m/s",
     "Primeiro converte: 36 km/h ÷ 3,6 = 10 m/s. Depois v = 10 + 2 × 5 = 20 m/s."],

    ["Biologia", "Genética", "Primeira lei de Mendel", 1, "facil", "conceito",
     "Do cruzamento entre um indivíduo AA e um indivíduo aa, qual é a proporção genotípica dos descendentes?",
     "100% Aa",
     "Um pai só forma gametas A e o outro só a: todos os filhos recebem A e a, logo 100% Aa."],
    ["Biologia", "Genética", "Primeira lei de Mendel", 2, "media", "calculo",
     "No cruzamento Aa × aa, qual é a probabilidade de um descendente ter fenótipo recessivo?",
     "1/2 (50%)",
     "Gametas A e a de um lado, só a do outro: Aa e aa em partes iguais. aa é recessivo, logo 1/2."],
    ["Biologia", "Genética", "Primeira lei de Mendel", 3, "media", "conceito",
     "No cruzamento Aa × Aa, com dominância completa, qual é a proporção fenotípica esperada?",
     "3 dominantes : 1 recessivo",
     "Genótipos 1 AA : 2 Aa : 1 aa. AA e Aa têm o mesmo fenótipo dominante, logo 3 : 1."],
    ["Biologia", "Genética", "Primeira lei de Mendel", 4, "media", "interpretacao",
     "No cruzamento Aa × Aa, entre os descendentes de fenótipo dominante, qual é a probabilidade de um deles ser heterozigoto?",
     "2/3",
     "Entre os dominantes (1 AA : 2 Aa) só contam 3 partes; 2 delas são Aa. Por isso 2/3, e não 1/2."],
    ["Biologia", "Genética", "Primeira lei de Mendel", 5, "dificil", "procedimento",
     "Um casal Aa × Aa planeja ter dois filhos. Qual é a probabilidade de os dois serem aa?",
     "1/16",
     "Cada filho tem 1/4 de chance de ser aa e os nascimentos são independentes: 1/4 × 1/4 = 1/16."],

    ["Português", "Sintaxe", "Orações subordinadas", 1, "facil", "conceito",
     "Em \"Saí cedo porque tinha prova\", que circunstância a oração \"porque tinha prova\" expressa?",
     "Causa",
     "\"Porque\" introduz o motivo de ter saído cedo: oração subordinada adverbial causal."],
    ["Português", "Sintaxe", "Orações subordinadas", 2, "media", "conceito",
     "Em \"Embora chovesse, fomos à praia\", como se classifica a oração \"Embora chovesse\"?",
     "Oração subordinada adverbial concessiva",
     "\"Embora\" apresenta um obstáculo que não impede o fato principal: é concessão, não causa."],
    ["Português", "Sintaxe", "Orações subordinadas", 3, "media", "interpretacao",
     "Em \"Se estudar, passará\", que relação a conjunção \"se\" estabelece entre as orações?",
     "Condição",
     "A aprovação depende do estudo: oração subordinada adverbial condicional."],
    ["Português", "Sintaxe", "Orações subordinadas", 4, "media", "conceito",
     "Em \"Estudou tanto que passou em primeiro lugar\", como se classifica a oração \"que passou em primeiro lugar\"?",
     "Oração subordinada adverbial consecutiva",
     "\"Tanto... que\" liga a causa intensa à sua consequência: oração consecutiva."],
    ["Português", "Sintaxe", "Orações subordinadas", 5, "dificil", "procedimento",
     "Reescreva \"Apesar de estar cansado, terminou a prova\" usando a conjunção \"embora\", sem mudar o sentido.",
     "Embora estivesse cansado, terminou a prova.",
     "\"Embora\" pede o verbo no subjuntivo (estivesse) e mantém a relação de concessão da frase original."]
  ]
  $json$;
begin
  for item in select * from jsonb_array_elements(itens) loop
    insert into public.catalog_exercises (
      subject, topic, theme, position, difficulty, error_category,
      prompt_text, reviewed_at, reviewed_by
    ) values (
      item->>0, item->>1, item->>2, (item->>3)::smallint, item->>4, item->>5,
      item->>6, revisao, 'Equipe MistakeMap'
    )
    on conflict (subject, topic, theme, position) do update set
      difficulty = excluded.difficulty,
      error_category = excluded.error_category,
      prompt_text = excluded.prompt_text,
      reviewed_at = excluded.reviewed_at,
      reviewed_by = excluded.reviewed_by
    returning id into cid;

    insert into public.catalog_answer_keys (catalog_exercise_id, correct_answer, explanation)
    values (cid, item->>7, item->>8)
    on conflict (catalog_exercise_id) do update set
      correct_answer = excluded.correct_answer,
      explanation = excluded.explanation;
  end loop;
end
$catalogo$;
