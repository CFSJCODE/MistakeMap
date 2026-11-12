-- Catálogo com temática de tecnologia.
--
-- Regra do projeto: todo exercício traz uma situação de tecnologia (robótica,
-- eletrônica, elétrica, hardware, software, programação, redes...) em que o
-- dispositivo ou sistema gera os dados do problema, sem mudar a matéria,
-- o conceito, a resposta, a dificuldade nem o tipo de erro treinado. Esta
-- migration revisa as 30 questões de 20261102003100_catalog_exercises.sql
-- pelo mesmo upsert (matéria, assunto, tema, posição).
--
-- Cópias do catálogo já entregues a alunos (exemplos e prática) recebem o
-- enunciado novo só enquanto ninguém respondeu: depois da primeira tentativa,
-- ou com gabarito de rodada, guard_analyzed_exercise trava o enunciado.

do $catalogo$
declare
  item jsonb;
  cid uuid;
  revisao constant timestamptz := '2026-11-02T17:30:00Z';
  itens constant jsonb := $json$
[
 [
  "Matemática",
  "Álgebra",
  "Equação do 1º grau",
  1,
  "facil",
  "calculo",
  "Um robô de competição já percorreu 3 m e avança 4 m a cada volta x do seu programa de teste. Para saber depois de quantas voltas ele chega a 19 m, resolva 4x + 3 = 19.",
  "x = 4",
  "4x = 19 - 3 = 16, logo x = 16 ÷ 4 = 4 voltas."
 ],
 [
  "Matemática",
  "Álgebra",
  "Equação do 1º grau",
  2,
  "facil",
  "sinal",
  "Na calibração de um sensor, a leitura corrigida é 5 - 2x, em que x é o offset aplicado (em unidades do conversor analógico-digital). Para a leitura corrigida dar 11, resolva 5 - 2x = 11.",
  "x = -3",
  "-2x = 11 - 5 = 6, logo x = 6 ÷ (-2) = -3. O sinal de menos acompanha o 2x, por isso o offset é negativo."
 ],
 [
  "Matemática",
  "Álgebra",
  "Equação do 1º grau",
  3,
  "media",
  "procedimento",
  "Dois downloads correm na mesma rede. O download A começa 2 s depois do cronômetro e baixa 3 MB/s, então já baixou 3(x - 2) MB; o download B começa junto com o cronômetro, com 5 MB já em cache, e baixa 2 MB/s, somando 2x + 5 MB. Em que instante x os dois terão baixado a mesma quantidade? Resolva 3(x - 2) = 2x + 5.",
  "x = 11 s",
  "Distribuindo: 3x - 6 = 2x + 5. Então 3x - 2x = 5 + 6, logo x = 11 s."
 ],
 [
  "Matemática",
  "Álgebra",
  "Equação do 1º grau",
  4,
  "media",
  "procedimento",
  "Um script em Python processou metade dos x arquivos de uma pasta na primeira execução e um terço deles na segunda, somando 10 arquivos. Quantos arquivos havia na pasta? Resolva x/2 + x/3 = 10.",
  "x = 12",
  "Com denominador comum 6: (3x + 2x)/6 = 10, logo 5x = 60 e x = 12 arquivos."
 ],
 [
  "Matemática",
  "Álgebra",
  "Equação do 1º grau",
  5,
  "media",
  "interpretacao",
  "Três sensores ligados ao mesmo barramento I2C têm endereços inteiros consecutivos, e a soma dos três endereços é 72. Quais são os endereços?",
  "23, 24 e 25",
  "Sendo x o menor: x + (x + 1) + (x + 2) = 72, logo 3x + 3 = 72, 3x = 69 e x = 23."
 ],
 [
  "Matemática",
  "Matemática financeira",
  "Porcentagem",
  1,
  "facil",
  "calculo",
  "A bateria de um robô aspirador armazena 240 Wh, e cada limpeza consome 15% dessa carga. Quantos Wh o robô gasta por limpeza?",
  "36 Wh",
  "15% = 0,15; 0,15 × 240 = 36 Wh."
 ],
 [
  "Matemática",
  "Matemática financeira",
  "Porcentagem",
  2,
  "media",
  "conceito",
  "Depois de uma otimização no código, um servidor passou a atender 92 requisições por segundo em vez de 80. Qual foi o aumento percentual de desempenho?",
  "15%",
  "O aumento foi de 12 requisições por segundo sobre o valor antigo: 12 ÷ 80 = 0,15 = 15%. A base é o valor inicial."
 ],
 [
  "Matemática",
  "Matemática financeira",
  "Porcentagem",
  3,
  "media",
  "conceito",
  "Ao ativar o modo econômico, a corrente consumida por um robô seguidor de linha caiu 25% e ficou em 60 mA. Qual era a corrente antes?",
  "80 mA",
  "Sobrou 75% da corrente: 60 ÷ 0,75 = 80 mA. Somar 25% sobre 60 daria 75 mA, que está errado."
 ],
 [
  "Matemática",
  "Matemática financeira",
  "Porcentagem",
  4,
  "media",
  "conceito",
  "O desempenho de um processador cai 10% por superaquecimento e, depois, mais 20% do que restou ao entrar no modo de economia de energia. As duas quedas equivalem a qual redução única?",
  "28%",
  "Os fatores se multiplicam: 0,90 × 0,80 = 0,72. Sobra 72% do desempenho, ou seja, redução de 28%, e não de 30%."
 ],
 [
  "Matemática",
  "Matemática financeira",
  "Porcentagem",
  5,
  "dificil",
  "conceito",
  "Durante uma oscilação na rede elétrica, a tensão que chega a uma bancada de testes caiu 20%. Em quanto por cento a tensão precisa subir, a partir desse valor, para voltar ao nível inicial?",
  "25%",
  "Depois da queda sobra 0,8 do inicial. Para voltar a 1: 1 ÷ 0,8 = 1,25, ou seja, alta de 25% sobre o valor já reduzido."
 ],
 [
  "Física",
  "Dinâmica",
  "Segunda lei de Newton",
  1,
  "facil",
  "conceito",
  "Os motores de um robô seguidor de linha de 6 kg produzem uma força resultante de 30 N. Qual é a aceleração do robô?",
  "5 m/s²",
  "F = m · a, logo a = F ÷ m = 30 ÷ 6 = 5 m/s²."
 ],
 [
  "Física",
  "Dinâmica",
  "Segunda lei de Newton",
  2,
  "facil",
  "calculo",
  "Qual força resultante os motores precisam produzir para acelerar um carro elétrico autônomo de 1.200 kg a 2 m/s²?",
  "2.400 N",
  "F = m · a = 1.200 × 2 = 2.400 N."
 ],
 [
  "Física",
  "Dinâmica",
  "Segunda lei de Newton",
  3,
  "media",
  "interpretacao",
  "O motor de passo de uma máquina CNC empurra a mesa de 5 kg com 40 N, e o atrito das guias vale 15 N. Qual é a aceleração da mesa?",
  "5 m/s²",
  "A resultante desconta o atrito: 40 - 15 = 25 N. Então a = 25 ÷ 5 = 5 m/s²."
 ],
 [
  "Física",
  "Dinâmica",
  "Segunda lei de Newton",
  4,
  "media",
  "sinal",
  "Um drone de 2 kg em voo horizontal recebe dos rotores um empuxo de 18 N para frente, e o vento o empurra com 10 N no sentido oposto. Qual é a aceleração e em que sentido?",
  "4 m/s², no sentido da força de 18 N",
  "Forças opostas se subtraem: 18 - 10 = 8 N no sentido da maior. a = 8 ÷ 2 = 4 m/s²."
 ],
 [
  "Física",
  "Dinâmica",
  "Segunda lei de Newton",
  5,
  "dificil",
  "procedimento",
  "Um elevador de 500 kg, comandado por um controlador lógico programável (CLP), sobe com aceleração constante de 2 m/s². Considerando g = 10 m/s², qual é a tração no cabo?",
  "6.000 N",
  "Para cima: T - P = m · a. Com P = 500 × 10 = 5.000 N, T = 5.000 + 500 × 2 = 6.000 N."
 ],
 [
  "Física",
  "Cinemática",
  "MRUV",
  1,
  "facil",
  "calculo",
  "Um carro elétrico parte do repouso com aceleração constante de 3 m/s². Qual é a velocidade dele após 4 s?",
  "12 m/s",
  "v = v0 + a · t = 0 + 3 × 4 = 12 m/s."
 ],
 [
  "Física",
  "Cinemática",
  "MRUV",
  2,
  "media",
  "procedimento",
  "Um drone de corrida parte do repouso com aceleração constante de 4 m/s². Que distância ele percorre em 3 s?",
  "18 m",
  "d = v0 · t + a · t²/2 = 0 + 4 × 9 ÷ 2 = 18 m. O tempo entra ao quadrado e o termo é dividido por 2."
 ],
 [
  "Física",
  "Cinemática",
  "MRUV",
  3,
  "media",
  "sinal",
  "Um carro autônomo a 20 m/s detecta um obstáculo com o LiDAR e freia com desaceleração constante de 5 m/s². Em quanto tempo ele para?",
  "4 s",
  "Na frenagem a aceleração é negativa: 0 = 20 - 5 · t, logo t = 4 s."
 ],
 [
  "Física",
  "Cinemática",
  "MRUV",
  4,
  "media",
  "procedimento",
  "Um carro autônomo a 20 m/s freia com desaceleração constante de 5 m/s² até parar. Qual distância o software de navegação deve reservar para a frenagem?",
  "40 m",
  "Torricelli: v² = v0² - 2 · a · d, então 0 = 400 - 10 · d e d = 40 m."
 ],
 [
  "Física",
  "Cinemática",
  "MRUV",
  5,
  "dificil",
  "unidade",
  "Um patinete elétrico a 36 km/h acelera a 2 m/s² durante 5 s. Qual é a velocidade final em m/s?",
  "20 m/s",
  "Primeiro converte: 36 km/h ÷ 3,6 = 10 m/s. Depois v = 10 + 2 × 5 = 20 m/s."
 ],
 [
  "Biologia",
  "Genética",
  "Primeira lei de Mendel",
  1,
  "facil",
  "conceito",
  "Um robô de laboratório automatiza cruzamentos de ervilhas e registra os descendentes com uma câmera. No cruzamento AA × aa, qual proporção genotípica deve ser registrada?",
  "100% Aa",
  "Um pai só forma gametas A e o outro só a: todos os filhos recebem A e a, logo 100% Aa."
 ],
 [
  "Biologia",
  "Genética",
  "Primeira lei de Mendel",
  2,
  "media",
  "calculo",
  "Um sistema de visão computacional classifica as sementes do cruzamento Aa × aa como lisas ou rugosas, sendo rugosa o fenótipo recessivo. Qual é a probabilidade de uma semente ser classificada como rugosa?",
  "1/2 (50%)",
  "Gametas A e a de um lado, só a do outro: Aa e aa em partes iguais. aa é recessivo, logo 1/2."
 ],
 [
  "Biologia",
  "Genética",
  "Primeira lei de Mendel",
  3,
  "media",
  "conceito",
  "Um programa em Python simula 10.000 cruzamentos Aa × Aa, com dominância completa, e conta os fenótipos. Qual proporção fenotípica o programa deve obter?",
  "3 dominantes : 1 recessivo",
  "Genótipos 1 AA : 2 Aa : 1 aa. AA e Aa têm o mesmo fenótipo dominante, logo 3 : 1."
 ],
 [
  "Biologia",
  "Genética",
  "Primeira lei de Mendel",
  4,
  "media",
  "interpretacao",
  "Um braço robótico separa ao acaso uma planta de fenótipo dominante, vinda do cruzamento Aa × Aa, para sequenciamento. Qual é a probabilidade de ela ser heterozigota?",
  "2/3",
  "Entre os dominantes (1 AA : 2 Aa) só contam 3 partes; 2 delas são Aa. Por isso 2/3, e não 1/2."
 ],
 [
  "Biologia",
  "Genética",
  "Primeira lei de Mendel",
  5,
  "dificil",
  "procedimento",
  "Um aplicativo de bioinformática calcula riscos para um casal Aa × Aa que planeja ter dois filhos. Qual probabilidade de os dois serem aa o aplicativo deve informar?",
  "1/16",
  "Cada filho tem 1/4 de chance de ser aa e os nascimentos são independentes: 1/4 × 1/4 = 1/16."
 ],
 [
  "Português",
  "Sintaxe",
  "Orações subordinadas",
  1,
  "facil",
  "conceito",
  "Em \"O robô parou porque a bateria acabou\", que circunstância a oração \"porque a bateria acabou\" expressa?",
  "Causa",
  "\"Porque\" introduz o motivo de o robô ter parado: oração subordinada adverbial causal."
 ],
 [
  "Português",
  "Sintaxe",
  "Orações subordinadas",
  2,
  "media",
  "conceito",
  "Em \"Embora o sensor ultrassônico estivesse com ruído, o robô desviou do obstáculo\", como se classifica a oração \"Embora o sensor ultrassônico estivesse com ruído\"?",
  "Oração subordinada adverbial concessiva",
  "\"Embora\" apresenta um obstáculo que não impede o fato principal: é concessão, não causa."
 ],
 [
  "Português",
  "Sintaxe",
  "Orações subordinadas",
  3,
  "media",
  "interpretacao",
  "Em \"Se o sensor detectar fumaça, o alarme dispara\", que relação a conjunção \"se\" estabelece entre as orações?",
  "Condição",
  "O disparo do alarme depende da detecção de fumaça: oração subordinada adverbial condicional."
 ],
 [
  "Português",
  "Sintaxe",
  "Orações subordinadas",
  4,
  "media",
  "conceito",
  "Em \"O código foi tão bem otimizado que o aplicativo abriu em um segundo\", como se classifica a oração \"que o aplicativo abriu em um segundo\"?",
  "Oração subordinada adverbial consecutiva",
  "\"Tão... que\" liga a causa intensa à sua consequência: oração consecutiva."
 ],
 [
  "Português",
  "Sintaxe",
  "Orações subordinadas",
  5,
  "dificil",
  "procedimento",
  "Reescreva \"Apesar de estar com pouca memória RAM, o computador compilou o projeto\" usando a conjunção \"embora\", sem mudar o sentido.",
  "Embora estivesse com pouca memória RAM, o computador compilou o projeto.",
  "\"Embora\" pede o verbo no subjuntivo (estivesse) e mantém a relação de concessão da frase original."
 ]
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

update public.exercises e
set prompt_text = c.prompt_text
from public.catalog_exercises c
where e.catalog_exercise_id = c.id
  and e.prompt_text is distinct from c.prompt_text
  and not exists (select 1 from public.attempts a where a.exercise_id = e.id)
  and not exists (
    select 1 from public.practice_answer_keys k where k.exercise_id = e.id
  );
