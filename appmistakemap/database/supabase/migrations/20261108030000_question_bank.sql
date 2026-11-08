-- Banco de questões da aba Exercícios: questões de vários tipos que o aluno
-- responde no próprio app (múltipla escolha, várias corretas, verdadeiro ou
-- falso, numérica, lacunas, ordenação, associação e dissertativa).
--
-- Regras:
-- - O app lê só o enunciado e os itens públicos (question_bank.payload). O
--   gabarito e o diagnóstico de cada alternativa ficam em question_bank_keys,
--   sem acesso do cliente; a Edge Function question-bank corrige no servidor.
-- - Cada resposta vira uma tentativa na conta do aluno (um exercício por
--   questão, ligado por exercises.question_id), com análise no mesmo formato
--   da IA. Assim o erro de uma questão objetiva entra no Mapa, no histórico e
--   na prática. A dissertativa é corrigida pela IA (analyze-attempt) com o
--   gabarito revisado como referência.
-- - Todo exercício tem temática de tecnologia (_shared/educational_context.ts).
--
-- O bloco de conteúdo é idempotente (upsert por slug): para revisar uma
-- questão, copie-o para uma migration nova.

create table public.question_bank (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{3,80}$'),
  subject text not null check (char_length(btrim(subject)) between 1 and 120),
  topic text not null check (char_length(btrim(topic)) between 1 and 120),
  theme text not null check (char_length(btrim(theme)) between 1 and 120),
  kind text not null check (kind in ('multipla_escolha', 'multipla_selecao',
    'verdadeiro_falso', 'numerica', 'lacuna', 'ordenacao', 'associacao',
    'dissertativa')),
  difficulty text not null check (difficulty in ('facil', 'media', 'dificil')),
  -- Tipo de erro treinado (mesma taxonomia da análise), usado quando a
  -- alternativa marcada não tem diagnóstico próprio.
  error_category text not null references public.error_types(name),
  prompt_text text not null check (char_length(btrim(prompt_text)) between 10 and 4000),
  -- Itens públicos: alternativas, afirmações, lacunas, itens a ordenar, colunas.
  payload jsonb not null default '{}' check (jsonb_typeof(payload) = 'object'),
  position integer not null,
  reviewed_at timestamptz not null,
  reviewed_by text not null
);

create index question_bank_position_idx on public.question_bank (position);

create table public.question_bank_keys (
  question_id uuid primary key references public.question_bank(id) on delete cascade,
  answer jsonb not null check (jsonb_typeof(answer) = 'object'),
  correct_answer text not null check (char_length(btrim(correct_answer)) > 0),
  explanation text not null check (char_length(btrim(explanation)) > 0)
);

alter table public.question_bank enable row level security;
alter table public.question_bank_keys enable row level security;

create policy question_bank_read on public.question_bank
  for select to authenticated using (true);

revoke all on public.question_bank from public, anon, authenticated;
grant select on public.question_bank to authenticated;
grant all on public.question_bank to service_role;

-- Sem política nem grant para o cliente: o gabarito só sai pela correção.
revoke all on public.question_bank_keys from public, anon, authenticated;
grant all on public.question_bank_keys to service_role;

-- Respostas do aluno (o app mostra a última de cada questão). Só o servidor
-- grava: a nota vem da correção, nunca do cliente.
create table public.question_responses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  question_id uuid not null references public.question_bank(id) on delete cascade,
  attempt_id uuid references public.attempts(id) on delete set null,
  response jsonb not null check (jsonb_typeof(response) = 'object'),
  -- Nulo enquanto a dissertativa espera a correção da IA.
  is_correct boolean,
  score numeric check (score is null or score between 0 and 1),
  created_at timestamptz not null default now()
);

create index question_responses_owner_idx
  on public.question_responses (user_id, question_id, created_at desc);
create index question_responses_attempt_idx
  on public.question_responses (attempt_id) where attempt_id is not null;

alter table public.question_responses enable row level security;

create policy question_responses_owner_read on public.question_responses
  for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.question_responses from public, anon, authenticated;
grant select on public.question_responses to authenticated;
grant all on public.question_responses to service_role;

-- Exercício do aluno que veio do banco de questões (nulo para os demais).
alter table public.exercises
  add column question_id uuid references public.question_bank(id) on delete set null;

create index exercises_question_idx on public.exercises (question_id)
  where question_id is not null;

-- Dissertativa analisada depois (pela fila ou pelo botão Analisar): a nota da
-- resposta acompanha a análise da IA. Sem HTTP: só um UPDATE local.
create or replace function public.sync_question_response_grade() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if jsonb_typeof(new.analysis -> 'is_correct') = 'boolean' then
    update public.question_responses
    set is_correct = (new.analysis ->> 'is_correct')::boolean,
        score = case when (new.analysis ->> 'is_correct')::boolean then 1 else 0 end
    where attempt_id = new.attempt_id and is_correct is null;
  end if;
  return new;
end;
$$;

revoke execute on function public.sync_question_response_grade() from public, anon, authenticated;

create trigger sync_question_response_grade after insert on public.attempt_analyses
  for each row execute function public.sync_question_response_grade();

-- ─── Conteúdo revisado ──────────────────────────────────────────────────────
-- 40 questões, 5 de cada tipo. Cada gabarito foi conferido; as alternativas
-- erradas trazem o tipo de erro que elas revelam.
do $banco$
declare
  item jsonb;
  qid uuid;
  revisao constant timestamptz := '2026-11-08T03:00:00Z';
  itens constant jsonb := $json$[
 {
  "slug": "me-ohm-led",
  "subject": "Eletrônica",
  "topic": "Circuitos",
  "theme": "Lei de Ohm",
  "kind": "multipla_escolha",
  "difficulty": "facil",
  "error_category": "calculo",
  "prompt_text": "O LED de status de um robô precisa de 20 mA. A fonte é de 5 V e o LED consome 3 V; o resistor em série fica com o resto da tensão. Qual resistor limita a corrente a 20 mA?",
  "payload": {
   "options": [
    {
     "id": "a",
     "text": "100 Ω"
    },
    {
     "id": "b",
     "text": "250 Ω"
    },
    {
     "id": "c",
     "text": "150 Ω"
    },
    {
     "id": "d",
     "text": "0,1 Ω"
    }
   ]
  },
  "answer": {
   "correct": "a",
   "diagnosis": {
    "b": {
     "category": "interpretacao",
     "feedback": "Você usou os 5 V da fonte inteiros. O resistor só recebe a sobra: 5 V − 3 V = 2 V."
    },
    "c": {
     "category": "conceito",
     "feedback": "Você usou a tensão do LED (3 V). Ao resistor cabe a diferença entre a fonte e o LED: 2 V."
    },
    "d": {
     "category": "unidade",
     "feedback": "20 mA = 0,020 A. Dividir 2 V por 20 (em vez de 0,020) deu 0,1."
    }
   }
  },
  "correct_answer": "a) 100 Ω",
  "explanation": "R = (5 V − 3 V) ÷ 0,020 A = 2 ÷ 0,020 = 100 Ω.",
  "position": 1
 },
 {
  "slug": "nu-resistores-serie",
  "subject": "Eletrônica",
  "topic": "Circuitos",
  "theme": "Associação de resistores",
  "kind": "numerica",
  "difficulty": "facil",
  "error_category": "calculo",
  "prompt_text": "Três resistores de 220 Ω, 330 Ω e 470 Ω estão ligados em série na placa de um robô. Qual é a resistência equivalente?",
  "payload": {
   "unit": "Ω"
  },
  "answer": {
   "value": 1020,
   "tolerance": 0.5,
   "common_errors": [
    {
     "value": 1.02,
     "tolerance": 0.005,
     "category": "unidade",
     "feedback": "Você respondeu em kΩ. A resposta pede ohms: 1,02 kΩ = 1020 Ω."
    },
    {
     "value": 103.06,
     "tolerance": 1,
     "category": "conceito",
     "feedback": "Esse valor é da associação em paralelo. Em série, as resistências se somam."
    }
   ]
  },
  "correct_answer": "1020 Ω",
  "explanation": "Em série: 220 + 330 + 470 = 1020 Ω.",
  "position": 2
 },
 {
  "slug": "vf-robo-newton",
  "subject": "Física",
  "topic": "Dinâmica",
  "theme": "Segunda lei de Newton",
  "kind": "verdadeiro_falso",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "Os motores de um robô de 5 kg o empurram com 40 N sobre um piso que exerce atrito de 15 N. Julgue cada afirmação.",
  "payload": {
   "statements": [
    {
     "id": "1",
     "text": "A força resultante sobre o robô é 25 N."
    },
    {
     "id": "2",
     "text": "A aceleração do robô é 8 m/s²."
    },
    {
     "id": "3",
     "text": "A aceleração do robô é 5 m/s²."
    },
    {
     "id": "4",
     "text": "Se o atrito subir para 40 N, o robô necessariamente fica parado."
    }
   ]
  },
  "answer": {
   "answers": {
    "1": true,
    "2": false,
    "3": true,
    "4": false
   },
   "diagnosis": {
    "1": {
     "category": "calculo",
     "feedback": "Resultante = 40 N − 15 N = 25 N."
    },
    "2": {
     "category": "conceito",
     "feedback": "8 m/s² usa só a força dos motores. A segunda lei usa a resultante: 25 N ÷ 5 kg."
    },
    "3": {
     "category": "calculo",
     "feedback": "a = 25 N ÷ 5 kg = 5 m/s²."
    },
    "4": {
     "category": "conceito",
     "feedback": "Com resultante nula a aceleração é zero: o robô mantém a velocidade que tinha e pode continuar andando."
    }
   }
  },
  "correct_answer": "1) V; 2) F; 3) V; 4) F",
  "explanation": "F resultante = 40 − 15 = 25 N e a = 25 ÷ 5 = 5 m/s². Resultante zero não para o robô: só zera a aceleração.",
  "position": 3
 },
 {
  "slug": "la-lei-ohm",
  "subject": "Eletrônica",
  "topic": "Circuitos",
  "theme": "Lei de Ohm",
  "kind": "lacuna",
  "difficulty": "facil",
  "error_category": "conceito",
  "prompt_text": "Complete sobre o circuito do robô: pela Lei de Ohm, a tensão é igual à resistência vezes a (1) ______. A unidade de resistência elétrica é o (2) ______.",
  "payload": {
   "blanks": [
    {
     "id": "1",
     "text": "Lacuna 1"
    },
    {
     "id": "2",
     "text": "Lacuna 2"
    }
   ]
  },
  "answer": {
   "answers": {
    "1": [
     "corrente",
     "corrente elétrica",
     "corrente eletrica",
     "i"
    ],
    "2": [
     "ohm",
     "ohms",
     "Ω"
    ]
   },
   "diagnosis": {
    "1": {
     "category": "conceito",
     "feedback": "V = R × I: a tensão é a resistência vezes a corrente."
    },
    "2": {
     "category": "unidade",
     "feedback": "Resistência se mede em ohm (Ω)."
    }
   }
  },
  "correct_answer": "(1) corrente; (2) ohm",
  "explanation": "V = R × I, com R em ohms (Ω).",
  "position": 4
 },
 {
  "slug": "ms-sensores",
  "subject": "Robótica",
  "topic": "Sensores e atuadores",
  "theme": "Sensores e atuadores",
  "kind": "multipla_selecao",
  "difficulty": "facil",
  "error_category": "conceito",
  "prompt_text": "Marque todos os componentes do robô que são SENSORES, isto é, que fornecem dados ao controlador.",
  "payload": {
   "options": [
    {
     "id": "a",
     "text": "Sensor ultrassônico HC-SR04"
    },
    {
     "id": "b",
     "text": "Motor DC"
    },
    {
     "id": "c",
     "text": "Encoder da roda"
    },
    {
     "id": "d",
     "text": "Servomotor"
    },
    {
     "id": "e",
     "text": "Giroscópio (IMU)"
    }
   ]
  },
  "answer": {
   "correct": [
    "a",
    "c",
    "e"
   ],
   "diagnosis": {
    "a": {
     "category": "conceito",
     "feedback": "O ultrassônico mede a distância pelo eco e envia esse dado: é sensor."
    },
    "b": {
     "category": "conceito",
     "feedback": "O motor DC recebe um comando e produz movimento: é atuador."
    },
    "c": {
     "category": "conceito",
     "feedback": "O encoder conta as voltas da roda e informa ao controlador: é sensor."
    },
    "d": {
     "category": "conceito",
     "feedback": "O servomotor recebe a posição desejada e se move: é atuador."
    },
    "e": {
     "category": "conceito",
     "feedback": "O giroscópio mede a rotação do robô: é sensor."
    }
   }
  },
  "correct_answer": "a, c, e",
  "explanation": "Sensores medem e informam (ultrassônico, encoder, giroscópio); atuadores executam (motor DC, servo).",
  "position": 5
 },
 {
  "slug": "as-componentes",
  "subject": "Eletrônica",
  "topic": "Componentes",
  "theme": "Componentes eletrônicos",
  "kind": "associacao",
  "difficulty": "facil",
  "error_category": "conceito",
  "prompt_text": "Associe cada componente da placa do robô à sua função.",
  "payload": {
   "left": [
    {
     "id": "l1",
     "text": "Resistor"
    },
    {
     "id": "l2",
     "text": "Capacitor"
    },
    {
     "id": "l3",
     "text": "Diodo"
    },
    {
     "id": "l4",
     "text": "Transistor"
    }
   ],
   "right": [
    {
     "id": "r3",
     "text": "Deixa a corrente passar num só sentido"
    },
    {
     "id": "r1",
     "text": "Limita a corrente"
    },
    {
     "id": "r4",
     "text": "Amplifica ou chaveia um sinal"
    },
    {
     "id": "r2",
     "text": "Armazena carga elétrica"
    }
   ]
  },
  "answer": {
   "pairs": {
    "l1": "r1",
    "l2": "r2",
    "l3": "r3",
    "l4": "r4"
   },
   "diagnosis": {
    "l1": {
     "category": "conceito",
     "feedback": "O resistor limita a corrente."
    },
    "l2": {
     "category": "conceito",
     "feedback": "O capacitor armazena carga elétrica."
    },
    "l3": {
     "category": "conceito",
     "feedback": "O diodo conduz num só sentido."
    },
    "l4": {
     "category": "conceito",
     "feedback": "O transistor amplifica ou funciona como chave."
    }
   }
  },
  "correct_answer": "Resistor → limita a corrente; Capacitor → armazena carga; Diodo → um só sentido; Transistor → amplifica/chaveia",
  "explanation": "Cada componente tem um papel: limitar (resistor), armazenar (capacitor), retificar (diodo) e amplificar/chavear (transistor).",
  "position": 6
 },
 {
  "slug": "or-boot-pc",
  "subject": "Computação",
  "topic": "Hardware",
  "theme": "Inicialização do computador",
  "kind": "ordenacao",
  "difficulty": "media",
  "error_category": "procedimento",
  "prompt_text": "Coloque em ordem as etapas da inicialização do computador de bordo de um robô, da primeira à última.",
  "payload": {
   "items": [
    {
     "id": "d",
     "text": "O kernel do sistema operacional é carregado"
    },
    {
     "id": "b",
     "text": "O firmware (BIOS/UEFI) faz o autoteste (POST)"
    },
    {
     "id": "e",
     "text": "O programa de controle do robô começa a rodar"
    },
    {
     "id": "a",
     "text": "A fonte é ligada e energiza a placa-mãe"
    },
    {
     "id": "c",
     "text": "O carregador de boot (bootloader) é lido do disco"
    }
   ]
  },
  "answer": {
   "order": [
    "a",
    "b",
    "c",
    "d",
    "e"
   ],
   "category": "procedimento",
   "feedback": "Energia → firmware/POST → bootloader → kernel → programas."
  },
  "correct_answer": "1. Fonte ligada; 2. Firmware/POST; 3. Bootloader; 4. Kernel; 5. Programa do robô",
  "explanation": "Sem energia nada roda; o firmware testa o hardware e acha o bootloader, que carrega o kernel, que então roda os programas.",
  "position": 7
 },
 {
  "slug": "di-pid-oscilacao",
  "subject": "Robótica",
  "topic": "Controle",
  "theme": "Controle PID",
  "kind": "dissertativa",
  "difficulty": "dificil",
  "error_category": "conceito",
  "prompt_text": "Um robô seguidor de linha oscila muito de um lado para o outro da linha. Explique o que fazem os termos P, I e D do controlador e qual ajuste você faria primeiro para reduzir a oscilação.",
  "payload": {},
  "answer": {},
  "correct_answer": "P reage ao erro atual (proporcional), I acumula o erro ao longo do tempo e elimina o erro residual, D reage à variação do erro e amortece. Para reduzir a oscilação: diminuir Kp e/ou aumentar Kd (e verificar se Ki não está alto).",
  "explanation": "Oscilação costuma vir de ganho proporcional alto demais ou de pouco amortecimento; o termo D freia mudanças rápidas e o I alto também causa overshoot.",
  "position": 8
 },
 {
  "slug": "me-drone-mruv",
  "subject": "Física",
  "topic": "Cinemática",
  "theme": "MRUV",
  "kind": "multipla_escolha",
  "difficulty": "media",
  "error_category": "procedimento",
  "prompt_text": "Um drone parte do repouso e sobe na vertical com aceleração constante de 2 m/s². Que altura ele atinge em 5 s?",
  "payload": {
   "options": [
    {
     "id": "a",
     "text": "10 m"
    },
    {
     "id": "b",
     "text": "25 m"
    },
    {
     "id": "c",
     "text": "50 m"
    },
    {
     "id": "d",
     "text": "100 m"
    }
   ]
  },
  "answer": {
   "correct": "b",
   "diagnosis": {
    "a": {
     "category": "conceito",
     "feedback": "a·t = 10 m/s é a velocidade do drone em 5 s, não a altura."
    },
    "c": {
     "category": "procedimento",
     "feedback": "Faltou dividir por 2: a altura é a·t²/2."
    },
    "d": {
     "category": "calculo",
     "feedback": "(a·t)² não é a fórmula da posição. Use s = a·t²/2."
    }
   }
  },
  "correct_answer": "b) 25 m",
  "explanation": "Partindo do repouso, s = a·t²/2 = 2 × 5² ÷ 2 = 25 m.",
  "position": 9
 },
 {
  "slug": "nu-odometria-roda",
  "subject": "Robótica",
  "topic": "Locomoção",
  "theme": "Odometria",
  "kind": "numerica",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "Um robô tem rodas de 6 cm de diâmetro. O encoder registra 10 voltas completas da roda, sem deslizar. Que distância o robô percorreu, em centímetros? Use π = 3,14.",
  "payload": {
   "unit": "cm"
  },
  "answer": {
   "value": 188.4,
   "tolerance": 0.2,
   "common_errors": [
    {
     "value": 376.8,
     "tolerance": 0.2,
     "category": "conceito",
     "feedback": "6 cm é o diâmetro, não o raio: o perímetro é π·d (ou 2π·r com r = 3 cm)."
    },
    {
     "value": 1.884,
     "tolerance": 0.002,
     "category": "unidade",
     "feedback": "Você converteu para metros, mas a pergunta pede centímetros."
    },
    {
     "value": 60,
     "tolerance": 0.1,
     "category": "procedimento",
     "feedback": "Faltou multiplicar por π: cada volta percorre o perímetro da roda, π·d."
    },
    {
     "value": 18.84,
     "tolerance": 0.02,
     "category": "interpretacao",
     "feedback": "18,84 cm é uma volta só; o encoder contou 10 voltas."
    }
   ]
  },
  "correct_answer": "188,4 cm",
  "explanation": "Perímetro = π·d = 3,14 × 6 = 18,84 cm por volta; 10 voltas = 188,4 cm.",
  "position": 10
 },
 {
  "slug": "vf-ipv4",
  "subject": "Redes de computadores",
  "topic": "Endereçamento",
  "theme": "Endereçamento IPv4",
  "kind": "verdadeiro_falso",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "Um robô está conectado ao roteador do laboratório com o IP 192.168.1.10 e máscara 255.255.255.0. Julgue cada afirmação.",
  "payload": {
   "statements": [
    {
     "id": "1",
     "text": "192.168.1.10 é um endereço IPv4 privado."
    },
    {
     "id": "2",
     "text": "O robô e uma câmera com IP 192.168.2.10 estão na mesma sub-rede."
    },
    {
     "id": "3",
     "text": "Um endereço IPv4 tem 32 bits."
    },
    {
     "id": "4",
     "text": "192.168.1.300 é um endereço IPv4 válido."
    }
   ]
  },
  "answer": {
   "answers": {
    "1": true,
    "2": false,
    "3": true,
    "4": false
   },
   "diagnosis": {
    "1": {
     "category": "conceito",
     "feedback": "A faixa 192.168.0.0/16 é reservada para redes privadas."
    },
    "2": {
     "category": "conceito",
     "feedback": "Com máscara 255.255.255.0 os três primeiros octetos precisam ser iguais; 1 ≠ 2."
    },
    "3": {
     "category": "conceito",
     "feedback": "IPv4 tem 4 octetos de 8 bits: 32 bits."
    },
    "4": {
     "category": "conceito",
     "feedback": "Cada octeto vai de 0 a 255; 300 não cabe em 8 bits."
    }
   }
  },
  "correct_answer": "1) V; 2) F; 3) V; 4) F",
  "explanation": "A máscara /24 compara os três primeiros octetos, e cada octeto vai de 0 a 255.",
  "position": 11
 },
 {
  "slug": "la-python-pisca",
  "subject": "Programação",
  "topic": "Laços de repetição",
  "theme": "Laço for",
  "kind": "lacuna",
  "difficulty": "facil",
  "error_category": "procedimento",
  "prompt_text": "Complete o código em Python que pisca o LED do robô 5 vezes:\n\nfor i in (1) ______(5):\n    led.on()\n    time.sleep(0.5)\n    led.off()\n    time.(2) ______(0.5)",
  "payload": {
   "blanks": [
    {
     "id": "1",
     "text": "Lacuna 1"
    },
    {
     "id": "2",
     "text": "Lacuna 2"
    }
   ]
  },
  "answer": {
   "answers": {
    "1": [
     "range"
    ],
    "2": [
     "sleep"
    ]
   },
   "diagnosis": {
    "1": {
     "category": "procedimento",
     "feedback": "range(5) gera 0, 1, 2, 3, 4: o laço roda 5 vezes."
    },
    "2": {
     "category": "procedimento",
     "feedback": "time.sleep(0.5) espera meio segundo com o LED apagado."
    }
   }
  },
  "correct_answer": "(1) range; (2) sleep",
  "explanation": "for i in range(5) repete 5 vezes e time.sleep(0.5) cria a pausa.",
  "position": 12
 },
 {
  "slug": "ms-transporte",
  "subject": "Redes de computadores",
  "topic": "Modelo TCP/IP",
  "theme": "Protocolos de transporte",
  "kind": "multipla_selecao",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "Um robô de inspeção transmite vídeo e telemetria pela rede. Marque os protocolos que pertencem à camada de TRANSPORTE do modelo TCP/IP.",
  "payload": {
   "options": [
    {
     "id": "a",
     "text": "TCP"
    },
    {
     "id": "b",
     "text": "UDP"
    },
    {
     "id": "c",
     "text": "IP"
    },
    {
     "id": "d",
     "text": "HTTP"
    },
    {
     "id": "e",
     "text": "Ethernet"
    }
   ]
  },
  "answer": {
   "correct": [
    "a",
    "b"
   ],
   "diagnosis": {
    "a": {
     "category": "conceito",
     "feedback": "TCP é de transporte: conexão confiável, com confirmação e reenvio."
    },
    "b": {
     "category": "conceito",
     "feedback": "UDP é de transporte: envia sem conexão, bom para vídeo ao vivo."
    },
    "c": {
     "category": "conceito",
     "feedback": "IP é da camada de rede (internet): endereça e roteia pacotes."
    },
    "d": {
     "category": "conceito",
     "feedback": "HTTP é da camada de aplicação."
    },
    "e": {
     "category": "conceito",
     "feedback": "Ethernet é da camada de enlace (acesso ao meio)."
    }
   }
  },
  "correct_answer": "a, b",
  "explanation": "TCP e UDP são os protocolos de transporte; IP é de rede, HTTP de aplicação e Ethernet de enlace.",
  "position": 13
 },
 {
  "slug": "as-unidades-eletricas",
  "subject": "Física",
  "topic": "Eletrodinâmica",
  "theme": "Unidades de medida",
  "kind": "associacao",
  "difficulty": "facil",
  "error_category": "unidade",
  "prompt_text": "No multímetro da bancada de robótica, associe cada grandeza à sua unidade.",
  "payload": {
   "left": [
    {
     "id": "l1",
     "text": "Corrente elétrica"
    },
    {
     "id": "l2",
     "text": "Tensão elétrica"
    },
    {
     "id": "l3",
     "text": "Potência"
    },
    {
     "id": "l4",
     "text": "Resistência"
    }
   ],
   "right": [
    {
     "id": "r2",
     "text": "volt (V)"
    },
    {
     "id": "r4",
     "text": "ohm (Ω)"
    },
    {
     "id": "r1",
     "text": "ampère (A)"
    },
    {
     "id": "r3",
     "text": "watt (W)"
    }
   ]
  },
  "answer": {
   "pairs": {
    "l1": "r1",
    "l2": "r2",
    "l3": "r3",
    "l4": "r4"
   },
   "diagnosis": {
    "l1": {
     "category": "unidade",
     "feedback": "Corrente se mede em ampère (A)."
    },
    "l2": {
     "category": "unidade",
     "feedback": "Tensão se mede em volt (V)."
    },
    "l3": {
     "category": "unidade",
     "feedback": "Potência se mede em watt (W)."
    },
    "l4": {
     "category": "unidade",
     "feedback": "Resistência se mede em ohm (Ω)."
    }
   }
  },
  "correct_answer": "Corrente → A; Tensão → V; Potência → W; Resistência → Ω",
  "explanation": "A, V, W e Ω são as unidades do SI dessas grandezas.",
  "position": 14
 },
 {
  "slug": "or-soldagem",
  "subject": "Eletrônica",
  "topic": "Montagem de circuitos",
  "theme": "Soldagem de componentes",
  "kind": "ordenacao",
  "difficulty": "facil",
  "error_category": "procedimento",
  "prompt_text": "Coloque em ordem os passos para soldar um resistor na placa de um robô.",
  "payload": {
   "items": [
    {
     "id": "c",
     "text": "Encostar o estanho na junção já aquecida"
    },
    {
     "id": "e",
     "text": "Cortar o excesso do terminal"
    },
    {
     "id": "a",
     "text": "Inserir o terminal do resistor no furo da placa"
    },
    {
     "id": "d",
     "text": "Retirar o estanho e depois o ferro"
    },
    {
     "id": "b",
     "text": "Aquecer ao mesmo tempo a ilha e o terminal com o ferro"
    }
   ]
  },
  "answer": {
   "order": [
    "a",
    "b",
    "c",
    "d",
    "e"
   ],
   "category": "procedimento",
   "feedback": "Posicionar → aquecer a junção → aplicar estanho → tirar estanho e ferro → cortar o excesso."
  },
  "correct_answer": "1. Inserir o terminal; 2. Aquecer ilha e terminal; 3. Aplicar o estanho; 4. Retirar estanho e ferro; 5. Cortar o excesso",
  "explanation": "O estanho deve derreter na junção aquecida (não na ponta do ferro); o excesso do terminal só é cortado depois da solda firme.",
  "position": 15
 },
 {
  "slug": "di-led-resistor",
  "subject": "Eletrônica",
  "topic": "Circuitos",
  "theme": "Lei de Ohm",
  "kind": "dissertativa",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "Explique por que um LED vermelho ligado direto numa bateria de 9 V, sem resistor, queima. Depois explique como calcular o resistor para que ele trabalhe com 2 V e 20 mA.",
  "payload": {},
  "answer": {},
  "correct_answer": "Sem resistor nada limita a corrente: o LED tem resistência muito baixa depois de conduzir, a corrente sobe muito acima dos ~20 mA e o aquece até queimar. R = (9 V − 2 V) ÷ 0,020 A = 350 Ω (usa-se o valor comercial acima, como 390 Ω).",
  "explanation": "O resistor fica com a diferença de tensão entre a fonte e o LED e limita a corrente pela Lei de Ohm.",
  "position": 16
 },
 {
  "slug": "me-servidor-porcentagem",
  "subject": "Matemática",
  "topic": "Matemática financeira",
  "theme": "Porcentagem",
  "kind": "multipla_escolha",
  "difficulty": "facil",
  "error_category": "calculo",
  "prompt_text": "Um servidor atendia 80 requisições por segundo. Depois de uma otimização no código, passou a atender 92. Qual foi o aumento percentual?",
  "payload": {
   "options": [
    {
     "id": "a",
     "text": "12%"
    },
    {
     "id": "b",
     "text": "13%"
    },
    {
     "id": "c",
     "text": "15%"
    },
    {
     "id": "d",
     "text": "115%"
    }
   ]
  },
  "answer": {
   "correct": "c",
   "diagnosis": {
    "a": {
     "category": "interpretacao",
     "feedback": "12 é o aumento em requisições. Em porcentagem, divida 12 pelo valor inicial (80)."
    },
    "b": {
     "category": "conceito",
     "feedback": "A base da porcentagem é o valor inicial (80), não o final (92)."
    },
    "d": {
     "category": "interpretacao",
     "feedback": "115% é o novo valor comparado ao antigo. O aumento é 115% − 100% = 15%."
    }
   }
  },
  "correct_answer": "c) 15%",
  "explanation": "Aumento = 92 − 80 = 12 requisições; 12 ÷ 80 = 0,15 = 15%.",
  "position": 17
 },
 {
  "slug": "nu-log-transmissao",
  "subject": "Redes de computadores",
  "topic": "Desempenho de redes",
  "theme": "Taxa de transmissão",
  "kind": "numerica",
  "difficulty": "media",
  "error_category": "unidade",
  "prompt_text": "Um robô envia um arquivo de log de 40 MB (megabytes) por uma rede de 80 Mbit/s, sem perdas nem sobrecarga. Quantos segundos leva a transmissão?",
  "payload": {
   "unit": "s"
  },
  "answer": {
   "value": 4,
   "tolerance": 0.01,
   "common_errors": [
    {
     "value": 0.5,
     "tolerance": 0.01,
     "category": "unidade",
     "feedback": "MB (megabyte) não é Mbit: 1 byte = 8 bits, então 40 MB = 320 Mbit."
    },
    {
     "value": 2,
     "tolerance": 0.01,
     "category": "calculo",
     "feedback": "Divida o tamanho em bits pela taxa: 320 Mbit ÷ 80 Mbit/s."
    }
   ]
  },
  "correct_answer": "4 s",
  "explanation": "40 MB × 8 = 320 Mbit; 320 Mbit ÷ 80 Mbit/s = 4 s.",
  "position": 18
 },
 {
  "slug": "vf-logica-bateria",
  "subject": "Programação",
  "topic": "Lógica booleana",
  "theme": "Operadores lógicos",
  "kind": "verdadeiro_falso",
  "difficulty": "facil",
  "error_category": "calculo",
  "prompt_text": "No programa de um robô, sensor_ok = True e bateria = 15 (em %). Julgue o resultado de cada expressão em Python.",
  "payload": {
   "statements": [
    {
     "id": "1",
     "text": "sensor_ok and bateria > 20 resulta em True."
    },
    {
     "id": "2",
     "text": "sensor_ok or bateria > 20 resulta em True."
    },
    {
     "id": "3",
     "text": "not sensor_ok resulta em False."
    },
    {
     "id": "4",
     "text": "bateria > 10 and bateria < 20 resulta em True."
    }
   ]
  },
  "answer": {
   "answers": {
    "1": false,
    "2": true,
    "3": true,
    "4": true
   },
   "diagnosis": {
    "1": {
     "category": "calculo",
     "feedback": "bateria > 20 é False (15 não é maior que 20), e and exige as duas partes True."
    },
    "2": {
     "category": "conceito",
     "feedback": "or basta uma parte True: sensor_ok já é True."
    },
    "3": {
     "category": "conceito",
     "feedback": "not inverte: not True é False."
    },
    "4": {
     "category": "calculo",
     "feedback": "15 > 10 é True e 15 < 20 é True, então o and dá True."
    }
   }
  },
  "correct_answer": "1) F; 2) V; 3) V; 4) V",
  "explanation": "and só é True com as duas partes True; or basta uma; not inverte o valor.",
  "position": 19
 },
 {
  "slug": "la-dhcp-dns",
  "subject": "Redes de computadores",
  "topic": "Serviços de rede",
  "theme": "DNS e DHCP",
  "kind": "lacuna",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "Quando o robô entra na rede Wi-Fi, o protocolo (1) ______ entrega a ele um endereço IP automaticamente. Para descobrir o IP do servidor api.robo.com, ele consulta o (2) ______.",
  "payload": {
   "blanks": [
    {
     "id": "1",
     "text": "Lacuna 1"
    },
    {
     "id": "2",
     "text": "Lacuna 2"
    }
   ]
  },
  "answer": {
   "answers": {
    "1": [
     "dhcp"
    ],
    "2": [
     "dns",
     "servidor dns",
     "servidor de dns"
    ]
   },
   "diagnosis": {
    "1": {
     "category": "conceito",
     "feedback": "DHCP distribui endereços IP automaticamente."
    },
    "2": {
     "category": "conceito",
     "feedback": "DNS traduz nomes (api.robo.com) em endereços IP."
    }
   }
  },
  "correct_answer": "(1) DHCP; (2) DNS",
  "explanation": "DHCP atribui o IP; DNS resolve nomes em IPs.",
  "position": 20
 },
 {
  "slug": "ms-primos-chaves",
  "subject": "Matemática",
  "topic": "Aritmética",
  "theme": "Números primos",
  "kind": "multipla_selecao",
  "difficulty": "facil",
  "error_category": "conceito",
  "prompt_text": "Um algoritmo de criptografia de um roteador escolhe chaves entre números primos. Marque todos os números primos.",
  "payload": {
   "options": [
    {
     "id": "a",
     "text": "2"
    },
    {
     "id": "b",
     "text": "9"
    },
    {
     "id": "c",
     "text": "17"
    },
    {
     "id": "d",
     "text": "21"
    },
    {
     "id": "e",
     "text": "1"
    },
    {
     "id": "f",
     "text": "29"
    }
   ]
  },
  "answer": {
   "correct": [
    "a",
    "c",
    "f"
   ],
   "diagnosis": {
    "a": {
     "category": "conceito",
     "feedback": "2 é primo: só é divisível por 1 e por ele mesmo (é o único primo par)."
    },
    "b": {
     "category": "calculo",
     "feedback": "9 = 3 × 3, então não é primo."
    },
    "c": {
     "category": "conceito",
     "feedback": "17 só é divisível por 1 e por 17: é primo."
    },
    "d": {
     "category": "calculo",
     "feedback": "21 = 3 × 7, então não é primo."
    },
    "e": {
     "category": "conceito",
     "feedback": "1 não é primo: um primo tem exatamente dois divisores."
    },
    "f": {
     "category": "conceito",
     "feedback": "29 só é divisível por 1 e por 29: é primo."
    }
   }
  },
  "correct_answer": "a, c, f",
  "explanation": "Primos têm exatamente dois divisores: 2, 17 e 29. 9 = 3×3, 21 = 3×7 e 1 tem um divisor só.",
  "position": 21
 },
 {
  "slug": "as-camadas-tcpip",
  "subject": "Redes de computadores",
  "topic": "Modelo TCP/IP",
  "theme": "Camadas de rede",
  "kind": "associacao",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "O robô envia telemetria a um painel web. Associe cada protocolo usado à sua camada no modelo TCP/IP.",
  "payload": {
   "left": [
    {
     "id": "l1",
     "text": "HTTP"
    },
    {
     "id": "l2",
     "text": "TCP"
    },
    {
     "id": "l3",
     "text": "IP"
    },
    {
     "id": "l4",
     "text": "Ethernet"
    }
   ],
   "right": [
    {
     "id": "r3",
     "text": "Rede (internet)"
    },
    {
     "id": "r1",
     "text": "Aplicação"
    },
    {
     "id": "r4",
     "text": "Enlace (acesso à rede)"
    },
    {
     "id": "r2",
     "text": "Transporte"
    }
   ]
  },
  "answer": {
   "pairs": {
    "l1": "r1",
    "l2": "r2",
    "l3": "r3",
    "l4": "r4"
   },
   "diagnosis": {
    "l1": {
     "category": "conceito",
     "feedback": "HTTP é protocolo de aplicação."
    },
    "l2": {
     "category": "conceito",
     "feedback": "TCP é de transporte."
    },
    "l3": {
     "category": "conceito",
     "feedback": "IP é da camada de rede (internet)."
    },
    "l4": {
     "category": "conceito",
     "feedback": "Ethernet é de enlace."
    }
   }
  },
  "correct_answer": "HTTP → Aplicação; TCP → Transporte; IP → Rede; Ethernet → Enlace",
  "explanation": "Da aplicação ao meio físico: HTTP (aplicação), TCP (transporte), IP (rede), Ethernet (enlace).",
  "position": 22
 },
 {
  "slug": "or-desenvolvimento-firmware",
  "subject": "Programação",
  "topic": "Desenvolvimento de software",
  "theme": "Ciclo de desenvolvimento",
  "kind": "ordenacao",
  "difficulty": "facil",
  "error_category": "procedimento",
  "prompt_text": "Coloque em ordem as etapas para colocar um programa novo no microcontrolador de um robô.",
  "payload": {
   "items": [
    {
     "id": "b",
     "text": "Compilar o código"
    },
    {
     "id": "d",
     "text": "Executar e testar no robô"
    },
    {
     "id": "a",
     "text": "Escrever o código-fonte"
    },
    {
     "id": "c",
     "text": "Gravar (fazer upload do) binário no microcontrolador"
    }
   ]
  },
  "answer": {
   "order": [
    "a",
    "b",
    "c",
    "d"
   ],
   "category": "procedimento",
   "feedback": "Escrever → compilar → gravar → testar."
  },
  "correct_answer": "1. Escrever; 2. Compilar; 3. Gravar; 4. Testar",
  "explanation": "Só dá para compilar o que foi escrito, só dá para gravar o binário compilado e só dá para testar o que foi gravado.",
  "position": 23
 },
 {
  "slug": "di-tcp-udp-robo",
  "subject": "Redes de computadores",
  "topic": "Modelo TCP/IP",
  "theme": "Protocolos de transporte",
  "kind": "dissertativa",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "Um robô transmite vídeo ao vivo para o operador e recebe comandos de parada de emergência. Qual protocolo de transporte (TCP ou UDP) você usaria para cada um? Justifique.",
  "payload": {},
  "answer": {},
  "correct_answer": "Vídeo ao vivo: UDP, porque perder um quadro é melhor que atrasar todos esperando reenvio. Parada de emergência: TCP (ou mecanismo com confirmação), porque o comando não pode se perder e precisa de confirmação de entrega.",
  "explanation": "UDP prioriza baixa latência sem garantia de entrega; TCP garante entrega e ordem com confirmação e reenvio.",
  "position": 24
 },
 {
  "slug": "me-byte-decimal",
  "subject": "Computação",
  "topic": "Sistemas de numeração",
  "theme": "Conversão binário-decimal",
  "kind": "multipla_escolha",
  "difficulty": "facil",
  "error_category": "procedimento",
  "prompt_text": "Um sensor digital envia o byte 00101101 ao microcontrolador. Qual é esse valor em decimal?",
  "payload": {
   "options": [
    {
     "id": "a",
     "text": "45"
    },
    {
     "id": "b",
     "text": "180"
    },
    {
     "id": "c",
     "text": "4"
    },
    {
     "id": "d",
     "text": "101101"
    }
   ]
  },
  "answer": {
   "correct": "a",
   "diagnosis": {
    "b": {
     "category": "procedimento",
     "feedback": "Você leu os bits ao contrário. O bit mais à direita vale 1, o seguinte 2, depois 4, 8…"
    },
    "c": {
     "category": "conceito",
     "feedback": "Contar quantos bits valem 1 não converte o número: cada posição vale uma potência de 2."
    },
    "d": {
     "category": "conceito",
     "feedback": "Tirar os zeros à esquerda não converte para decimal: some as potências de 2 dos bits 1."
    }
   }
  },
  "correct_answer": "a) 45",
  "explanation": "00101101 = 32 + 8 + 4 + 1 = 45.",
  "position": 25
 },
 {
  "slug": "nu-bateria-drone",
  "subject": "Matemática",
  "topic": "Matemática financeira",
  "theme": "Porcentagem",
  "kind": "numerica",
  "difficulty": "facil",
  "error_category": "calculo",
  "prompt_text": "A bateria de um drone tem capacidade de 5000 mAh e o aplicativo mostra 35% de carga. Quantos mAh restam na bateria?",
  "payload": {
   "unit": "mAh"
  },
  "answer": {
   "value": 1750,
   "tolerance": 0.5,
   "common_errors": [
    {
     "value": 3250,
     "tolerance": 0.5,
     "category": "interpretacao",
     "feedback": "3250 mAh é o que já foi gasto (65%). Restam 35% de 5000."
    },
    {
     "value": 175,
     "tolerance": 0.5,
     "category": "calculo",
     "feedback": "35% = 0,35, não 0,035: 0,35 × 5000 = 1750."
    }
   ]
  },
  "correct_answer": "1750 mAh",
  "explanation": "35% de 5000 = 0,35 × 5000 = 1750 mAh.",
  "position": 26
 },
 {
  "slug": "vf-bateria-eletroquimica",
  "subject": "Química",
  "topic": "Eletroquímica",
  "theme": "Pilhas e baterias",
  "kind": "verdadeiro_falso",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "A bateria de um robô está alimentando os motores (descarga). Julgue cada afirmação.",
  "payload": {
   "statements": [
    {
     "id": "1",
     "text": "Na descarga, a oxidação ocorre no ânodo."
    },
    {
     "id": "2",
     "text": "Pelo circuito externo, os elétrons saem do cátodo e vão para o ânodo."
    },
    {
     "id": "3",
     "text": "Na descarga, o ânodo é o polo negativo."
    },
    {
     "id": "4",
     "text": "Na redução, a espécie química ganha elétrons."
    }
   ]
  },
  "answer": {
   "answers": {
    "1": true,
    "2": false,
    "3": true,
    "4": true
   },
   "diagnosis": {
    "1": {
     "category": "conceito",
     "feedback": "Ânodo é onde ocorre a oxidação, por definição."
    },
    "2": {
     "category": "conceito",
     "feedback": "Os elétrons liberados na oxidação saem do ânodo e vão pelo fio até o cátodo."
    },
    "3": {
     "category": "conceito",
     "feedback": "Na pilha em descarga o ânodo libera elétrons: é o polo negativo."
    },
    "4": {
     "category": "conceito",
     "feedback": "Redução é ganho de elétrons."
    }
   }
  },
  "correct_answer": "1) V; 2) F; 3) V; 4) V",
  "explanation": "Ânodo: oxidação, polo negativo na descarga. Os elétrons vão do ânodo ao cátodo pelo circuito externo.",
  "position": 27
 },
 {
  "slug": "la-sensor-equacao",
  "subject": "Matemática",
  "topic": "Álgebra",
  "theme": "Equação do 1º grau",
  "kind": "lacuna",
  "difficulty": "facil",
  "error_category": "calculo",
  "prompt_text": "Um sensor converte a temperatura T (°C) na leitura L = 2T + 10. Para uma leitura L = 70: 2T = (1) ______, logo T = (2) ______ °C.",
  "payload": {
   "blanks": [
    {
     "id": "1",
     "text": "Lacuna 1"
    },
    {
     "id": "2",
     "text": "Lacuna 2"
    }
   ]
  },
  "answer": {
   "answers": {
    "1": [
     "60"
    ],
    "2": [
     "30",
     "30 °c",
     "30°c"
    ]
   },
   "diagnosis": {
    "1": {
     "category": "calculo",
     "feedback": "Passe o 10 subtraindo: 2T = 70 − 10 = 60."
    },
    "2": {
     "category": "calculo",
     "feedback": "T = 60 ÷ 2 = 30 °C."
    }
   }
  },
  "correct_answer": "(1) 60; (2) 30",
  "explanation": "2T + 10 = 70 → 2T = 60 → T = 30 °C.",
  "position": 28
 },
 {
  "slug": "ms-pwm-motor",
  "subject": "Eletrônica",
  "topic": "Sinais digitais",
  "theme": "PWM",
  "kind": "multipla_selecao",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "Um ESP32 controla a velocidade de um motor por PWM em 3,3 V. Marque as afirmações corretas.",
  "payload": {
   "options": [
    {
     "id": "a",
     "text": "Aumentar o duty cycle aumenta a tensão média no motor."
    },
    {
     "id": "b",
     "text": "O PWM varia a amplitude (a altura) da tensão de saída."
    },
    {
     "id": "c",
     "text": "Com duty cycle de 50%, a tensão média é 1,65 V."
    },
    {
     "id": "d",
     "text": "A frequência do PWM é o que define a velocidade do motor."
    },
    {
     "id": "e",
     "text": "Com duty cycle de 0%, o motor fica parado."
    }
   ]
  },
  "answer": {
   "correct": [
    "a",
    "c",
    "e"
   ],
   "diagnosis": {
    "a": {
     "category": "conceito",
     "feedback": "Mais tempo em nível alto por período significa tensão média maior."
    },
    "b": {
     "category": "conceito",
     "feedback": "O PWM mantém a amplitude (3,3 V) e varia a largura do pulso."
    },
    "c": {
     "category": "calculo",
     "feedback": "Tensão média = duty × 3,3 V = 0,5 × 3,3 = 1,65 V."
    },
    "d": {
     "category": "conceito",
     "feedback": "Quem define a velocidade é o duty cycle; a frequência só precisa ser alta o bastante."
    },
    "e": {
     "category": "conceito",
     "feedback": "0% de duty é saída sempre em nível baixo: o motor não recebe energia."
    }
   }
  },
  "correct_answer": "a, c, e",
  "explanation": "O PWM troca a largura do pulso, não a amplitude: a tensão média é duty × 3,3 V.",
  "position": 29
 },
 {
  "slug": "as-estruturas-dados",
  "subject": "Programação",
  "topic": "Estruturas de dados",
  "theme": "Estruturas de dados",
  "kind": "associacao",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "O software de um robô de estoque guarda dados de jeitos diferentes. Associe cada estrutura ao seu comportamento.",
  "payload": {
   "left": [
    {
     "id": "l1",
     "text": "Lista"
    },
    {
     "id": "l2",
     "text": "Dicionário"
    },
    {
     "id": "l3",
     "text": "Fila"
    },
    {
     "id": "l4",
     "text": "Pilha"
    }
   ],
   "right": [
    {
     "id": "r4",
     "text": "O último a entrar é o primeiro a sair"
    },
    {
     "id": "r2",
     "text": "Guarda pares chave → valor"
    },
    {
     "id": "r1",
     "text": "Sequência ordenada acessada por índice"
    },
    {
     "id": "r3",
     "text": "O primeiro a entrar é o primeiro a sair"
    }
   ]
  },
  "answer": {
   "pairs": {
    "l1": "r1",
    "l2": "r2",
    "l3": "r3",
    "l4": "r4"
   },
   "diagnosis": {
    "l1": {
     "category": "conceito",
     "feedback": "Lista: sequência ordenada acessada por índice."
    },
    "l2": {
     "category": "conceito",
     "feedback": "Dicionário: pares chave → valor."
    },
    "l3": {
     "category": "conceito",
     "feedback": "Fila (FIFO): o primeiro a entrar sai primeiro."
    },
    "l4": {
     "category": "conceito",
     "feedback": "Pilha (LIFO): o último a entrar sai primeiro."
    }
   }
  },
  "correct_answer": "Lista → índice; Dicionário → chave → valor; Fila → FIFO; Pilha → LIFO",
  "explanation": "Fila é FIFO (pedidos na ordem de chegada) e pilha é LIFO (desfazer a última ação).",
  "position": 30
 },
 {
  "slug": "or-handshake-tcp",
  "subject": "Redes de computadores",
  "topic": "Modelo TCP/IP",
  "theme": "Handshake TCP",
  "kind": "ordenacao",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "O app de controle abre uma conexão TCP com o robô. Coloque em ordem as mensagens trocadas.",
  "payload": {
   "items": [
    {
     "id": "c",
     "text": "O app envia ACK"
    },
    {
     "id": "a",
     "text": "O app envia SYN"
    },
    {
     "id": "d",
     "text": "Os comandos começam a ser enviados"
    },
    {
     "id": "b",
     "text": "O robô responde com SYN-ACK"
    }
   ]
  },
  "answer": {
   "order": [
    "a",
    "b",
    "c",
    "d"
   ],
   "category": "conceito",
   "feedback": "O handshake de três vias é SYN → SYN-ACK → ACK; só depois vêm os dados."
  },
  "correct_answer": "1. SYN; 2. SYN-ACK; 3. ACK; 4. Dados",
  "explanation": "TCP abre a conexão com o handshake de três vias (SYN, SYN-ACK, ACK) antes de enviar dados.",
  "position": 31
 },
 {
  "slug": "di-busca-binaria",
  "subject": "Programação",
  "topic": "Algoritmos",
  "theme": "Busca linear e binária",
  "kind": "dissertativa",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "Um robô de estoque precisa encontrar um código numa lista ordenada de 1 milhão de códigos. Compare a busca linear e a busca binária para essa tarefa e diga qual você usaria.",
  "payload": {},
  "answer": {},
  "correct_answer": "A busca linear olha um por um: no pior caso 1 milhão de comparações (O(n)). A busca binária usa a ordenação e corta a lista ao meio a cada passo: cerca de 20 comparações (log₂ 1.000.000 ≈ 20, O(log n)). Usaria a binária, já que a lista está ordenada.",
  "explanation": "A binária só funciona em lista ordenada, e é aí que ela ganha: cada comparação descarta metade dos candidatos.",
  "position": 32
 },
 {
  "slug": "me-oracao-temporal",
  "subject": "Português",
  "topic": "Sintaxe",
  "theme": "Orações subordinadas",
  "kind": "multipla_escolha",
  "difficulty": "media",
  "error_category": "conceito",
  "prompt_text": "No manual de um robô aspirador está escrito: \"O motor desliga quando o sensor detecta um obstáculo.\" A oração \"quando o sensor detecta um obstáculo\" é:",
  "payload": {
   "options": [
    {
     "id": "a",
     "text": "subordinada adverbial temporal"
    },
    {
     "id": "b",
     "text": "subordinada adjetiva restritiva"
    },
    {
     "id": "c",
     "text": "coordenada sindética aditiva"
    },
    {
     "id": "d",
     "text": "subordinada substantiva objetiva direta"
    }
   ]
  },
  "answer": {
   "correct": "a",
   "diagnosis": {
    "b": {
     "category": "conceito",
     "feedback": "A oração adjetiva caracteriza um substantivo (\"o sensor que detecta…\"). Aqui \"quando\" indica o momento em que o motor desliga."
    },
    "c": {
     "category": "conceito",
     "feedback": "A oração depende da principal e é introduzida por conjunção subordinativa (\"quando\"); não é coordenada."
    },
    "d": {
     "category": "conceito",
     "feedback": "Ela não completa o verbo \"desliga\"; indica uma circunstância de tempo."
    }
   }
  },
  "correct_answer": "a) subordinada adverbial temporal",
  "explanation": "\"Quando\" é conjunção subordinativa temporal: a oração diz em que momento o motor desliga.",
  "position": 33
 },
 {
  "slug": "nu-frenagem-robo",
  "subject": "Física",
  "topic": "Cinemática",
  "theme": "MRUV",
  "kind": "numerica",
  "difficulty": "media",
  "error_category": "sinal",
  "prompt_text": "Um carrinho robô a 4 m/s freia com desaceleração constante de 2 m/s² até parar. Que distância ele percorre durante a frenagem, em metros?",
  "payload": {
   "unit": "m"
  },
  "answer": {
   "value": 4,
   "tolerance": 0.01,
   "common_errors": [
    {
     "value": -4,
     "tolerance": 0.01,
     "category": "sinal",
     "feedback": "A distância não é negativa. Com a = −2 m/s²: 0 = 4² + 2·(−2)·Δs, então Δs = +4 m."
    },
    {
     "value": 8,
     "tolerance": 0.01,
     "category": "procedimento",
     "feedback": "Faltou o 2 de v² = v₀² + 2·a·Δs: Δs = 16 ÷ (2 × 2) = 4 m."
    },
    {
     "value": 2,
     "tolerance": 0.01,
     "category": "interpretacao",
     "feedback": "2 s é o tempo da frenagem; a pergunta pede a distância."
    }
   ]
  },
  "correct_answer": "4 m",
  "explanation": "Torricelli: 0 = 4² + 2·(−2)·Δs → 16 = 4·Δs → Δs = 4 m.",
  "position": 34
 },
 {
  "slug": "vf-carregador-energia",
  "subject": "Física",
  "topic": "Eletrodinâmica",
  "theme": "Potência e energia elétrica",
  "kind": "verdadeiro_falso",
  "difficulty": "media",
  "error_category": "unidade",
  "prompt_text": "Um carregador de 20 W fica ligado por 3 horas carregando a bateria de um robô. Julgue cada afirmação.",
  "payload": {
   "statements": [
    {
     "id": "1",
     "text": "A energia consumida foi de 60 Wh."
    },
    {
     "id": "2",
     "text": "60 Wh equivalem a 0,6 kWh."
    },
    {
     "id": "3",
     "text": "Um carregador de 5 V e 2 A tem potência de 10 W."
    },
    {
     "id": "4",
     "text": "Energia em kWh = potência em W × tempo em minutos."
    }
   ]
  },
  "answer": {
   "answers": {
    "1": true,
    "2": false,
    "3": true,
    "4": false
   },
   "diagnosis": {
    "1": {
     "category": "calculo",
     "feedback": "E = P × t = 20 W × 3 h = 60 Wh."
    },
    "2": {
     "category": "unidade",
     "feedback": "1 kWh = 1000 Wh, então 60 Wh = 0,06 kWh."
    },
    "3": {
     "category": "calculo",
     "feedback": "P = V × I = 5 V × 2 A = 10 W."
    },
    "4": {
     "category": "unidade",
     "feedback": "kWh é kW × hora: converta W para kW (÷ 1000) e minutos para horas (÷ 60)."
    }
   }
  },
  "correct_answer": "1) V; 2) F; 3) V; 4) F",
  "explanation": "E = P × t = 60 Wh = 0,06 kWh; P = V × I; kWh usa kW e horas.",
  "position": 35
 },
 {
  "slug": "la-portas-logicas",
  "subject": "Eletrônica",
  "topic": "Eletrônica digital",
  "theme": "Portas lógicas",
  "kind": "lacuna",
  "difficulty": "facil",
  "error_category": "conceito",
  "prompt_text": "No circuito de segurança do robô, uma porta (1) ______ só dá saída 1 quando todas as entradas são 1. Já uma porta (2) ______ inverte o sinal de entrada.",
  "payload": {
   "blanks": [
    {
     "id": "1",
     "text": "Lacuna 1"
    },
    {
     "id": "2",
     "text": "Lacuna 2"
    }
   ]
  },
  "answer": {
   "answers": {
    "1": [
     "and",
     "e"
    ],
    "2": [
     "not",
     "não",
     "nao",
     "inversora"
    ]
   },
   "diagnosis": {
    "1": {
     "category": "conceito",
     "feedback": "A porta AND (E) exige todas as entradas em 1."
    },
    "2": {
     "category": "conceito",
     "feedback": "A porta NOT (inversora) troca 0 por 1 e 1 por 0."
    }
   }
  },
  "correct_answer": "(1) AND; (2) NOT",
  "explanation": "AND: saída 1 só com todas as entradas em 1. NOT: inverte a entrada.",
  "position": 36
 },
 {
  "slug": "ms-python-int",
  "subject": "Programação",
  "topic": "Tipos de dados",
  "theme": "Tipos de dados",
  "kind": "multipla_selecao",
  "difficulty": "facil",
  "error_category": "conceito",
  "prompt_text": "Num programa em Python que lê sensores, quais destes valores são do tipo int?",
  "payload": {
   "options": [
    {
     "id": "a",
     "text": "42"
    },
    {
     "id": "b",
     "text": "3.0"
    },
    {
     "id": "c",
     "text": "'7'"
    },
    {
     "id": "d",
     "text": "-15"
    },
    {
     "id": "e",
     "text": "10 ** 3"
    }
   ]
  },
  "answer": {
   "correct": [
    "a",
    "d",
    "e"
   ],
   "diagnosis": {
    "a": {
     "category": "conceito",
     "feedback": "42 é um inteiro: int."
    },
    "b": {
     "category": "conceito",
     "feedback": "3.0 tem ponto decimal: é float."
    },
    "c": {
     "category": "conceito",
     "feedback": "'7' está entre aspas: é texto (str)."
    },
    "d": {
     "category": "conceito",
     "feedback": "-15 é inteiro negativo: int."
    },
    "e": {
     "category": "conceito",
     "feedback": "10 ** 3 vale 1000, um int."
    }
   }
  },
  "correct_answer": "a, d, e",
  "explanation": "42, -15 e 10 ** 3 (= 1000) são int; 3.0 é float e '7' é str.",
  "position": 37
 },
 {
  "slug": "as-sensores-funcao",
  "subject": "Robótica",
  "topic": "Sensores e atuadores",
  "theme": "Sensores e atuadores",
  "kind": "associacao",
  "difficulty": "facil",
  "error_category": "conceito",
  "prompt_text": "Associe cada sensor do robô ao que ele mede.",
  "payload": {
   "left": [
    {
     "id": "l1",
     "text": "Ultrassônico"
    },
    {
     "id": "l2",
     "text": "Encoder"
    },
    {
     "id": "l3",
     "text": "Giroscópio"
    },
    {
     "id": "l4",
     "text": "LDR"
    }
   ],
   "right": [
    {
     "id": "r2",
     "text": "Conta as voltas da roda"
    },
    {
     "id": "r4",
     "text": "Varia a resistência com a luz"
    },
    {
     "id": "r1",
     "text": "Mede distância pelo eco do som"
    },
    {
     "id": "r3",
     "text": "Mede a rotação (velocidade angular)"
    }
   ]
  },
  "answer": {
   "pairs": {
    "l1": "r1",
    "l2": "r2",
    "l3": "r3",
    "l4": "r4"
   },
   "diagnosis": {
    "l1": {
     "category": "conceito",
     "feedback": "O ultrassônico mede distância pelo tempo do eco."
    },
    "l2": {
     "category": "conceito",
     "feedback": "O encoder conta as voltas (ou pulsos) da roda."
    },
    "l3": {
     "category": "conceito",
     "feedback": "O giroscópio mede a velocidade angular."
    },
    "l4": {
     "category": "conceito",
     "feedback": "O LDR muda a resistência conforme a luz."
    }
   }
  },
  "correct_answer": "Ultrassônico → distância; Encoder → voltas; Giroscópio → rotação; LDR → luz",
  "explanation": "Cada sensor transforma uma grandeza física em sinal: som (distância), pulsos (voltas), rotação e luz.",
  "position": 38
 },
 {
  "slug": "or-laco-controle",
  "subject": "Robótica",
  "topic": "Controle",
  "theme": "Laço de controle",
  "kind": "ordenacao",
  "difficulty": "media",
  "error_category": "procedimento",
  "prompt_text": "Coloque em ordem um ciclo do laço de controle de um robô seguidor de linha.",
  "payload": {
   "items": [
    {
     "id": "d",
     "text": "Ajustar a velocidade dos motores"
    },
    {
     "id": "a",
     "text": "Ler o sensor de linha"
    },
    {
     "id": "c",
     "text": "Calcular a correção (PID)"
    },
    {
     "id": "e",
     "text": "Esperar o próximo ciclo"
    },
    {
     "id": "b",
     "text": "Calcular o erro em relação ao centro da linha"
    }
   ]
  },
  "answer": {
   "order": [
    "a",
    "b",
    "c",
    "d",
    "e"
   ],
   "category": "procedimento",
   "feedback": "Medir → calcular o erro → calcular a correção → atuar → esperar o próximo ciclo."
  },
  "correct_answer": "1. Ler o sensor; 2. Calcular o erro; 3. Calcular a correção; 4. Ajustar os motores; 5. Esperar",
  "explanation": "Todo laço de controle mede, compara com o desejado (erro), decide a correção e atua, repetindo a cada ciclo.",
  "position": 39
 },
 {
  "slug": "di-texto-instrucional-lipo",
  "subject": "Português",
  "topic": "Produção de texto",
  "theme": "Texto instrucional",
  "kind": "dissertativa",
  "difficulty": "media",
  "error_category": "procedimento",
  "prompt_text": "Escreva um parágrafo curto (3 a 5 frases) ensinando um colega a conectar com segurança a bateria LiPo do robô. Use conectivos de sequência (primeiro, em seguida, por fim) e verbos no imperativo.",
  "payload": {},
  "answer": {},
  "correct_answer": "Exemplo: Primeiro, desligue o interruptor do robô e confira se a bateria não está estufada. Em seguida, encaixe o conector respeitando a polaridade (vermelho no positivo). Depois, prenda a bateria com a fita de velcro. Por fim, ligue o robô e observe se há aquecimento.",
  "explanation": "Texto instrucional usa imperativo, ordem clara e conectivos de sequência; a correção avalia clareza, ordem e segurança.",
  "position": 40
 }
]$json$;
begin
  for item in select value from jsonb_array_elements(itens) loop
    insert into public.question_bank as q (slug, subject, topic, theme, kind,
      difficulty, error_category, prompt_text, payload, position, reviewed_at,
      reviewed_by)
    values (item ->> 'slug', item ->> 'subject', item ->> 'topic',
      item ->> 'theme', item ->> 'kind', item ->> 'difficulty',
      item ->> 'error_category', item ->> 'prompt_text', item -> 'payload',
      (item ->> 'position')::integer, revisao, 'MistakeMap')
    on conflict (slug) do update set subject = excluded.subject,
      topic = excluded.topic, theme = excluded.theme, kind = excluded.kind,
      difficulty = excluded.difficulty, error_category = excluded.error_category,
      prompt_text = excluded.prompt_text, payload = excluded.payload,
      position = excluded.position, reviewed_at = excluded.reviewed_at,
      reviewed_by = excluded.reviewed_by
    returning q.id into qid;

    insert into public.question_bank_keys (question_id, answer, correct_answer,
      explanation)
    values (qid, item -> 'answer', item ->> 'correct_answer',
      item ->> 'explanation')
    on conflict (question_id) do update set answer = excluded.answer,
      correct_answer = excluded.correct_answer,
      explanation = excluded.explanation;
  end loop;
end;
$banco$;
