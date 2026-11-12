-- seed_conta_teste.sql
-- Popula a conta de demonstração (teste@mistakemap.dev) com seis semanas de
-- uso realista de um estudante do ensino médio que se prepara para o ENEM:
-- matérias, exercícios, respostas, análises da IA, erros por conceito e acertos
-- que mostram evolução ao longo do tempo.
--
-- Uso (servidor, nunca no app): rode no SQL Editor do Supabase ou com
--   psql "$SUPABASE_DB_URL" -v email=teste@mistakemap.dev -f scripts/seed_conta_teste.sql
-- Sem -v, vale o e-mail padrão abaixo. Não usa service_role no cliente: roda
-- direto no banco com o papel do dono, fora do alcance do app.
--
-- Idempotente: apaga e recria só as matérias marcadas com a descrição de seed
-- (a cascata leva exercícios, tentativas, análises e eventos). Dados criados
-- pelo próprio estudante ficam intactos. As datas são relativas a now(), então
-- rodar de novo mantém o histórico recente.

\if :{?email}
\else
  \set email 'teste@mistakemap.dev'
\endif
select set_config('seed.email', :'email', false);

do $seed$
declare
  marca constant text := 'Dados de demonstração (seed)';
  uid uuid;
  materias jsonb := $json$
  [
    {"nome": "Matemática", "descricao": "Funções, equações, porcentagem e trigonometria"},
    {"nome": "Física", "descricao": "Cinemática, dinâmica e energia"},
    {"nome": "Biologia", "descricao": "Citologia, genética e ecologia"},
    {"nome": "Português", "descricao": "Interpretação de texto e gramática"}
  ]
  $json$;
  -- [matéria, dias atrás, dificuldade, enunciado, resposta do aluno,
  --  acertou, gabarito, explicação, conceitos, erros [categoria, conceito, evidência]]
  itens jsonb := $json$
  [
    ["Matemática", 41, "facil", "Resolva a equação 3x - 7 = 2x + 5.", "x = -2", false, "x = 12", "Isolando x: 3x - 2x = 5 + 7, logo x = 12.", ["Equação do 1º grau"], [["sinal", "Equação do 1º grau", "Passou o -7 para o outro lado como -7 em vez de +7."]]],
    ["Matemática", 39, "media", "Uma loja dá 20% de desconto e depois mais 10% sobre o novo preço. Qual o desconto total?", "30%", false, "28%", "0,8 × 0,9 = 0,72; o desconto total é 1 - 0,72 = 28%.", ["Porcentagem"], [["conceito", "Porcentagem", "Somou os descontos sucessivos (20% + 10%) em vez de multiplicar os fatores."]]],
    ["Matemática", 36, "media", "Encontre as raízes de x² - 5x + 6 = 0.", "x = -2 e x = -3", false, "x = 2 e x = 3", "Soma das raízes = 5 e produto = 6, logo 2 e 3.", ["Equação do 2º grau"], [["sinal", "Equação do 2º grau", "Trocou o sinal das raízes ao usar soma e produto."]]],
    ["Matemática", 33, "facil", "Qual o valor de f(3) para f(x) = 2x² - x + 1?", "16", true, "16", "f(3) = 2·9 - 3 + 1 = 16.", ["Função quadrática"], []],
    ["Matemática", 29, "media", "Um capital de R$ 1.000 rende 2% ao mês em juros compostos. Qual o montante após 2 meses?", "R$ 1.040,00", false, "R$ 1.040,40", "M = 1000 · 1,02² = 1040,40.", ["Juros compostos", "Porcentagem"], [["conceito", "Juros compostos", "Calculou juros simples (2% + 2%) em vez de compostos."]]],
    ["Matemática", 24, "dificil", "Em um triângulo retângulo, o cateto oposto a 30° mede 5 cm. Quanto mede a hipotenusa?", "5√3 cm", false, "10 cm", "sen 30° = 1/2 = 5/h, logo h = 10 cm.", ["Trigonometria"], [["procedimento", "Trigonometria", "Usou a tangente no lugar do seno para relacionar cateto oposto e hipotenusa."]]],
    ["Matemática", 19, "media", "Resolva 2x - 9 = 5x + 3.", "x = -4", true, "x = -4", "-3x = 12, logo x = -4.", ["Equação do 1º grau"], []],
    ["Matemática", 15, "media", "Um produto de R$ 200 sobe 10% e depois cai 10%. Qual o preço final?", "R$ 198,00", true, "R$ 198,00", "200 · 1,1 · 0,9 = 198.", ["Porcentagem"], []],
    ["Matemática", 10, "media", "Determine as raízes de x² + x - 12 = 0.", "x = 3 e x = -4", true, "x = 3 e x = -4", "Soma -1 e produto -12: 3 e -4.", ["Equação do 2º grau"], []],
    ["Matemática", 4, "dificil", "Uma escada de 6 m forma 60° com o chão. A que altura ela toca a parede?", "3 m", false, "3√3 m ≈ 5,2 m", "A altura é o cateto oposto a 60°: 6 · sen 60° = 3√3 m.", ["Trigonometria"], [["procedimento", "Trigonometria", "Usou cos 60° no lugar de sen 60° para o cateto oposto."]]],

    ["Física", 40, "facil", "Um carro percorre 150 km em 2 h. Qual a velocidade média em m/s?", "75 m/s", false, "≈ 20,8 m/s", "75 km/h ÷ 3,6 ≈ 20,8 m/s.", ["Velocidade média", "Conversão de unidades"], [["unidade", "Conversão de unidades", "Deu a resposta em km/h rotulada como m/s, sem dividir por 3,6."]]],
    ["Física", 35, "media", "Um corpo de 4 kg sofre força resultante de 20 N. Qual a aceleração?", "80 m/s²", false, "5 m/s²", "a = F/m = 20/4 = 5 m/s².", ["Segunda lei de Newton"], [["conceito", "Segunda lei de Newton", "Multiplicou força e massa em vez de dividir."]]],
    ["Física", 30, "media", "Uma bola é solta de 20 m de altura (g = 10 m/s²). Com que velocidade chega ao solo?", "20 m/s", true, "20 m/s", "v² = 2gh = 400, logo v = 20 m/s.", ["Queda livre"], []],
    ["Física", 26, "media", "Um móvel parte do repouso com a = 2 m/s². Que distância percorre em 5 s?", "10 m", false, "25 m", "d = a·t²/2 = 2·25/2 = 25 m.", ["MRUV"], [["procedimento", "MRUV", "Usou d = a·t, esquecendo o quadrado do tempo e a divisão por 2."]]],
    ["Física", 21, "media", "Qual a energia cinética de um corpo de 2 kg a 3 m/s?", "9 J", true, "9 J", "Ec = m·v²/2 = 2·9/2 = 9 J.", ["Energia cinética"], []],
    ["Física", 13, "facil", "Um ciclista faz 18 km em 30 min. Qual a velocidade média em m/s?", "10 m/s", true, "10 m/s", "36 km/h ÷ 3,6 = 10 m/s.", ["Velocidade média", "Conversão de unidades"], []],
    ["Física", 6, "dificil", "Um bloco de 10 kg é puxado por 50 N num piso com atrito de 20 N. Qual a aceleração?", "5 m/s²", false, "3 m/s²", "Resultante = 50 - 20 = 30 N; a = 30/10 = 3 m/s².", ["Segunda lei de Newton", "Atrito"], [["interpretacao", "Atrito", "Ignorou a força de atrito ao calcular a resultante."]]],

    ["Biologia", 38, "facil", "Qual organela realiza a respiração celular?", "Cloroplasto", false, "Mitocôndria", "A mitocôndria produz ATP pela respiração celular; o cloroplasto faz fotossíntese.", ["Organelas celulares"], [["conceito", "Organelas celulares", "Confundiu a função da mitocôndria com a do cloroplasto."]]],
    ["Biologia", 31, "media", "No cruzamento Aa × Aa, qual a proporção de descendentes com fenótipo recessivo?", "50%", false, "25%", "Genótipos 1 AA : 2 Aa : 1 aa; só aa é recessivo, 1/4.", ["Primeira lei de Mendel"], [["calculo", "Primeira lei de Mendel", "Contou Aa como recessivo ao montar o quadro de Punnett."]]],
    ["Biologia", 22, "media", "Em uma cadeia alimentar, qual o nível trófico do gafanhoto que come capim?", "Consumidor primário", true, "Consumidor primário", "Herbívoros ocupam o primeiro nível de consumidores.", ["Cadeia alimentar"], []],
    ["Biologia", 16, "media", "Qual organela é responsável pela síntese de proteínas?", "Ribossomo", true, "Ribossomo", "Ribossomos traduzem o RNA mensageiro em proteínas.", ["Organelas celulares"], []],
    ["Biologia", 8, "dificil", "Pais com sangue A (heterozigoto) e B (heterozigoto). Qual a chance de um filho tipo O?", "0%", false, "25%", "IAi × IBi gera 1/4 de ii, tipo O.", ["Grupos sanguíneos", "Primeira lei de Mendel"], [["conceito", "Grupos sanguíneos", "Não considerou o alelo i recessivo presente nos dois pais heterozigotos."]]],

    ["Português", 37, "media", "Em \"Embora estivesse cansado, terminou a prova\", qual a relação expressa pela oração destacada (\"Embora estivesse cansado\")?", "Causa", false, "Concessão", "\"Embora\" introduz oração subordinada adverbial concessiva.", ["Orações subordinadas"], [["interpretacao", "Orações subordinadas", "Confundiu concessão com causa."]]],
    ["Português", 28, "facil", "Assinale a forma correta: \"Fazem dois anos\" ou \"Faz dois anos\"?", "Faz dois anos", true, "Faz dois anos", "Fazer indicando tempo decorrido é impessoal.", ["Concordância verbal"], []],
    ["Português", 20, "media", "Qual a função da linguagem predominante em um anúncio que diz \"Compre já!\"?", "Referencial", false, "Conativa (apelativa)", "O foco no receptor, com verbo no imperativo, caracteriza a função conativa.", ["Funções da linguagem"], [["conceito", "Funções da linguagem", "Classificou como referencial um texto centrado em convencer o leitor."]]],
    ["Português", 11, "media", "Em \"Haviam muitas pessoas na fila\", há erro? Justifique.", "Sim, o correto é \"Havia\", pois haver no sentido de existir é impessoal.", true, "Havia muitas pessoas", "Haver com sentido de existir fica no singular.", ["Concordância verbal"], []],
    ["Português", 3, "media", "\"Estudou muito, por isso foi aprovado.\" Que relação a conjunção estabelece?", "Conclusão", true, "Conclusão (consequência)", "\"Por isso\" introduz oração coordenada conclusiva.", ["Orações coordenadas"], []]
  ]
  $json$;
  m jsonb;
  item jsonb;
  erro jsonb;
  conceito text;
  sid uuid;
  eid uuid;
  aid uuid;
  cid uuid;
  quando timestamptz;
  correto boolean;
  analise jsonb;
begin
  select id into uid from auth.users where email = current_setting('seed.email');
  if uid is null then
    raise exception 'Conta % não encontrada. Crie e confirme a conta antes do seed.',
      current_setting('seed.email');
  end if;

  delete from public.subjects where user_id = uid and description like marca || '%';

  for m in select * from jsonb_array_elements(materias) loop
    insert into public.subjects(user_id, name, description, created_at)
    values (uid, m->>'nome', marca || ' · ' || (m->>'descricao'), now() - interval '43 days');
  end loop;

  for item in select * from jsonb_array_elements(itens) loop
    select id into sid from public.subjects
      where user_id = uid and name = item->>0 and description like marca || '%';
    -- Horário de estudo variado à noite, para o histórico parecer real.
    quando := date_trunc('day', now()) - make_interval(days => (item->>1)::int)
      + make_interval(hours => 18 + ((item->>1)::int % 5), mins => ((item->>1)::int * 7) % 60);
    correto := (item->>5)::boolean;

    insert into public.exercises(subject_id, source, prompt_text, difficulty, created_at)
    values (sid, null, item->>3, item->>2, quando) returning id into eid;

    insert into public.attempts(exercise_id, user_id, answer, attempted_at, status, version)
    values (eid, uid, item->>4, quando, 'completed', 3) returning id into aid;

    analise := jsonb_build_object(
      'is_correct', correto,
      'correct_answer', item->>6,
      'explanation', item->>7,
      'transcribed_prompt', item->>3,
      'transcribed_answer', item->>4,
      'concepts', item->8,
      'errors', coalesce((
        select jsonb_agg(jsonb_build_object(
          'category', e->>0, 'concept', e->>1, 'evidence', e->>2, 'confidence', 0.85))
        from jsonb_array_elements(item->9) e), '[]'::jsonb)
    );
    insert into public.attempt_analyses(attempt_id, user_id, subject_id, analysis, model, pipeline_version, created_at)
    values (aid, uid, sid, analise, 'seed-demo', 'gemini-analysis-v1', quando + interval '2 minutes');
    insert into public.corrections(attempt_id, reference_text, created_at)
    values (aid, (item->>6) || E'\n\n' || (item->>7), quando + interval '2 minutes');

    for conceito in select * from jsonb_array_elements_text(item->8) loop
      select id into cid from public.concepts
        where subject_id = sid and lower(name) = lower(conceito) limit 1;
      if cid is null then
        insert into public.concepts(subject_id, name, created_at)
        values (sid, conceito, quando) returning id into cid;
      end if;
      insert into public.exercise_concepts(exercise_id, concept_id)
      values (eid, cid) on conflict do nothing;
      if correto then
        insert into public.mastery_events(concept_id, attempt_id, outcome, created_at)
        values (cid, aid, 'ai_suggested_correct', quando + interval '2 minutes');
      end if;
    end loop;

    for erro in select * from jsonb_array_elements(item->9) loop
      select id into cid from public.concepts
        where subject_id = sid and lower(name) = lower(erro->>1) limit 1;
      insert into public.error_events(attempt_id, error_type_id, concept_id, evidence_ref, confidence, status, created_at)
      select aid, t.id, cid, erro->>2, 0.85, 'pending', quando + interval '2 minutes'
      from public.error_types t where t.name = erro->>0;
    end loop;
  end loop;

  raise notice 'Seed concluído: % matérias, % exercícios.',
    jsonb_array_length(materias), jsonb_array_length(itens);
end
$seed$;
