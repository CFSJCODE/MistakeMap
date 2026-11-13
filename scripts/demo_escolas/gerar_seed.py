#!/usr/bin/env python3
"""Gera seed.sql e remover.sql: histórico realista de um aluno no MistakeMap.

Todos os ids são uuid5 determinísticos (namespace fixo), então remover.sql
apaga exatamente o que seed.sql criou. As datas são relativas a now() no
momento da execução: o histórico cobre as últimas ~4 semanas.
Uso: python3 gerar_seed.py <user_id>  -> seed-<id>.sql e remover-<id>.sql
"""
import json, uuid, hashlib, pathlib, sys

NS = uuid.UUID("6b1f3c1e-7d0a-4c52-9a43-6d6d64656d6f")
USER = sys.argv[1] if len(sys.argv) > 1 else "__USER_ID__"
NS_USER = uuid.uuid5(NS, USER)  # ids distintos por conta
def uid(key: str) -> str:
    return str(uuid.uuid5(NS_USER, "mmdemo:" + key))
def q(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"
def ago(h: float) -> str:
    return f"(t0 - interval '{h} hours')"
def js(o) -> str:
    return q(json.dumps(o, ensure_ascii=False)) + "::jsonb"

MARK = "Histórico de demonstração (mmdemo)"
SUBJECTS = {
    "ELE": "Eletrônica",
    "ROB": "Robótica",
    "RED": "Redes de computadores",
    "PRG": "Programação",
}
CONCEPTS = {  # key: (subject, name, importance)
    "ohm": ("ELE", "Lei de Ohm", 1.5),
    "div": ("ELE", "Divisor de tensão", 1.2),
    "pot": ("ELE", "Potência elétrica", 1.0),
    "pid": ("ROB", "Controle PID", 1.5),
    "odo": ("ROB", "Odometria", 1.0),
    "pwm": ("ROB", "PWM de motores", 1.0),
    "cin": ("ROB", "Cinemática diferencial", 1.0),
    "sub": ("RED", "Sub-redes IPv4", 1.2),
    "tcp": ("RED", "TCP x UDP", 1.0),
    "dhcp": ("RED", "DNS e DHCP", 1.0),
    "int": ("PRG", "Tipos inteiros e overflow", 1.0),
    "isr": ("PRG", "Interrupções (ISR)", 1.2),
    "deb": ("PRG", "Debounce de botão", 1.0),
}
EDGES = [("ohm", "div", "pre_requisito"), ("ohm", "pot", "pre_requisito"),
         ("pwm", "pid", "relacionado"), ("odo", "cin", "pre_requisito"),
         ("int", "isr", "relacionado"), ("isr", "deb", "relacionado")]

# exercício: (subject, dificuldade, enunciado, gabarito, explicação, conceitos)
EX = {
 "E1": ("ELE", "facil", "O LED de status de um ESP32 precisa de 15 mA. O pino entrega 3,3 V e o LED tem queda de 2,0 V. Qual resistor deve ficar em série com o LED?",
        "R ≈ 87 Ω (use o comercial de 100 Ω)", "O resistor recebe 3,3 − 2,0 = 1,3 V. R = 1,3 V ÷ 0,015 A ≈ 87 Ω; o valor comercial acima é 100 Ω.", ["ohm"]),
 "E2": ("ELE", "media", "O sensor NTC de temperatura de uma estufa automatizada forma um divisor com R1 = 10 kΩ (em cima) e o NTC embaixo, alimentados em 5 V; o ADC do Arduino lê a tensão sobre o NTC. Quanto o ADC lê quando o NTC vale 4,7 kΩ?",
        "Vout ≈ 1,60 V", "Vout = 5 V × 4,7 ÷ (10 + 4,7) = 5 × 0,32 ≈ 1,60 V. A saída é a tensão sobre o resistor de baixo (o NTC).", ["div", "ohm"]),
 "E3": ("ELE", "media", "A placa de controle de um robô consome 2 A em 7,4 V, entregues por um regulador com 80% de eficiência. Qual potência a placa consome e quanto a bateria precisa fornecer?",
        "Placa: 14,8 W; bateria: 18,5 W", "P = 7,4 V × 2 A = 14,8 W. Com 80% de eficiência, a bateria fornece 14,8 ÷ 0,8 = 18,5 W.", ["pot"]),
 "E4": ("ELE", "facil", "A bobina do motor de passo de uma impressora 3D tem 2,8 Ω e o driver está ajustado para 1200 mA. Qual a tensão sobre a bobina?",
        "V = 3,36 V", "1200 mA = 1,2 A. V = R × I = 2,8 Ω × 1,2 A = 3,36 V.", ["ohm"]),
 "E5": ("ROB", "media", "O robô seguidor de linha usa PID com Kp = 2,0, Ki = 0,5 e Kd = 0 e oscila em torno da linha com amplitude crescente. O que ajustar primeiro?",
        "Reduzir Kp e acrescentar um pouco de Kd", "Kp alto causa overshoot e o integral acumula erro e piora a oscilação. O derivativo reage à velocidade do erro e amortece.", ["pid"]),
 "E6": ("ROB", "media", "A roda do robô explorador tem 6,5 cm de diâmetro e o encoder gera 360 pulsos por volta. Quantos pulsos o robô conta para andar 1 m?",
        "≈ 1763 pulsos", "Circunferência = π × 6,5 cm ≈ 20,42 cm. 100 ÷ 20,42 ≈ 4,90 voltas × 360 ≈ 1763 pulsos.", ["odo"]),
 "E7": ("ROB", "facil", "O driver L298N do robô recebe PWM de 8 bits do Arduino (0 a 255) e a bateria é de 12 V. Qual duty cycle dá cerca de 6 V médios no motor e que valor vai no analogWrite?",
        "50%, analogWrite(128)", "6 V é metade de 12 V, logo 50% de duty. Em 8 bits, 50% de 255 ≈ 128.", ["pwm"]),
 "E8": ("ROB", "media", "Um robô de tração diferencial tem 12 cm entre as rodas. A roda esquerda anda a 0,20 m/s e a direita a 0,30 m/s. Qual a velocidade angular do robô?",
        "ω ≈ +0,83 rad/s (gira no sentido anti-horário)", "ω = (vD − vE) ÷ L = (0,30 − 0,20) ÷ 0,12 ≈ 0,83 rad/s. Com a roda direita mais rápida, o robô vira para a esquerda (anti-horário, ω positivo).", ["cin"]),
 "E9": ("RED", "media", "A rede do laboratório de robótica é 192.168.10.0/26 e precisa atender 50 sensores IoT. Quantos hosts utilizáveis a sub-rede tem e qual é o endereço de broadcast?",
        "62 hosts; broadcast 192.168.10.63", "/26 deixa 6 bits de host: 2⁶ = 64 endereços, menos rede e broadcast = 62. O bloco vai de .0 a .63, então o broadcast é .63.", ["sub"]),
 "E10": ("RED", "facil", "Um drone transmite vídeo ao vivo para a estação de solo. TCP ou UDP é mais adequado para esse fluxo? Por quê?",
        "UDP", "No vídeo ao vivo um quadro atrasado já não serve. O TCP retransmite e segura os seguintes (latência); o UDP entrega o que chega e o codec tolera perdas.", ["tcp"]),
 "E11": ("RED", "facil", "A câmera IP do robô de inspeção recebe o endereço 169.254.37.12 ao ligar e ninguém consegue acessá-la. Qual serviço falhou?",
        "DHCP (a câmera caiu no APIPA)", "169.254.0.0/16 é o endereço automático (APIPA) que o dispositivo se dá quando nenhum servidor DHCP responde. DNS só traduz nomes.", ["dhcp"]),
 "E12": ("PRG", "facil", "No firmware de um ESP32, um contador uint8_t soma os pulsos do encoder. Depois de 300 pulsos, que valor ele mostra?",
        "44", "uint8_t vai de 0 a 255 e volta a 0 ao estourar: 300 mod 256 = 44.", ["int"]),
 "E13": ("PRG", "media", "O botão de parada de emergência de um braço robótico às vezes registra três toques em um só aperto. Por que isso acontece e como corrigir no firmware?",
        "Repique mecânico (bounce); aplicar debounce de 20 a 50 ms", "O contato metálico quica por alguns milissegundos. Ignore mudanças por 20 a 50 ms após a primeira borda (ou use filtro RC).", ["deb"]),
 "E14": ("PRG", "dificil", "A rotina de interrupção (ISR) do sensor de fim de curso do braço robótico chama delay(100) e Serial.print. Qual o problema e como reescrever?",
        "A ISR deve ser curta: só marcar uma flag volatile e tratar no loop", "Dentro da ISR delay() não avança e Serial pode travar. Marque uma variável volatile e faça o trabalho pesado no loop principal.", ["isr"]),
}
# tentativa: (exercício, horas atrás, resposta, acertou, erros[(categoria, conceito, evidência, confiança)])
AT = [
 ("A1", "E1", 626, "R = 1,3 ÷ 15 = 0,087 Ω", False, [("unidade", "ohm", "Dividiu 1,3 V por 15 em vez de 0,015 A: a corrente ficou em mA e não em ampères.", 0.9)]),
 ("A2", "E1", 290, "R = 1,3 ÷ 0,015 ≈ 87 Ω, uso 100 Ω", True, []),
 ("A3", "E2", 482, "Vout = 5 × 10 ÷ 14,7 = 3,40 V", False, [("conceito", "div", "Colocou R1 (o resistor de cima) no numerador; a saída lida pelo ADC é a tensão sobre o NTC.", 0.85)]),
 ("A4", "E2", 50, "Vout = 2,5 V porque os resistores são iguais", False, [("interpretacao", "div", "Ignorou que o NTC passou a valer 4,7 kΩ e usou os 10 kΩ nominais.", 0.7)]),
 ("A5", "E3", 410, "P = 14,8 × 0,8 = 11,84 W", False, [("procedimento", "pot", "Multiplicou pela eficiência; para achar o que a bateria fornece é preciso dividir por 0,8.", 0.8)]),
 ("A6", "E3", 122, "Placa 14,8 W; bateria 14,8 ÷ 0,8 = 18,5 W", True, []),
 ("A7", "E4", 218, "V = 2,8 × 1200 = 3360 V", False, [("unidade", "ohm", "Usou 1200 mA como se fossem 1200 A; o resultado de 3360 V não faz sentido para um driver de impressora.", 0.9)]),
 ("A8", "E4", 6, "V = 2,8 × 0,12 = 0,336 V", False, [("unidade", "ohm", "Converteu 1200 mA para 0,12 A; o certo é 1,2 A.", 0.8)]),
 ("A9", "E5", 554, "Aumentar o Ki para corrigir mais rápido", False, [("conceito", "pid", "Atribuiu ao termo integral a função de amortecer; o integral acumula erro e aumenta a oscilação.", 0.85)]),
 ("A10", "E5", 194, "Aumentar o Kp para o robô voltar mais forte à linha", False, [("conceito", "pid", "Aumentar Kp aumenta o overshoot; a oscilação crescente pede menos Kp e algum Kd.", 0.8)]),
 ("A11", "E5", 26, "Diminuir Kp e colocar um pouco de Kd para amortecer", True, []),
 ("A12", "E6", 362, "2π × 6,5 = 40,8 cm por volta; 100 ÷ 40,8 × 360 ≈ 882 pulsos", False, [("conceito", "odo", "Usou o diâmetro como raio em 2πr; a volta mede π × d = 20,4 cm.", 0.8)]),
 ("A13", "E6", 98, "π × 6,5 = 20,42 cm; 4,9 voltas × 360 ≈ 1763 pulsos", True, []),
 ("A14", "E7", 266, "analogWrite(6)", False, [("interpretacao", "pwm", "Escreveu a tensão desejada (6) em vez do valor de 0 a 255 do PWM.", 0.9)]),
 ("A15", "E7", 74, "50% de duty, analogWrite(128)", True, []),
 ("A16", "E8", 170, "ω = (0,20 − 0,30) ÷ 0,12 = −0,83 rad/s, gira no sentido horário", False, [("sinal", "cin", "Inverteu a ordem vD − vE; com a roda direita mais rápida o robô gira no sentido anti-horário (ω positivo).", 0.75)]),
 ("A17", "E9", 458, "64 hosts; broadcast 192.168.10.64", False, [("calculo", "sub", "Não descontou os endereços de rede e de broadcast, e .64 já é a próxima sub-rede; o broadcast é .63.", 0.85)]),
 ("A18", "E9", 46, "62 hosts; broadcast 192.168.10.255", False, [("calculo", "sub", "Usou o broadcast da /24 inteira; na /26 o bloco termina em .63.", 0.8)]),
 ("A19", "E10", 314, "TCP, porque garante que todos os quadros cheguem", False, [("conceito", "tcp", "Retransmitir quadros atrasados aumenta a latência; vídeo ao vivo prioriza tempo, não entrega garantida.", 0.8)]),
 ("A20", "E11", 146, "O DNS da rede está fora do ar", False, [("conceito", "dhcp", "169.254.x.x é APIPA, sinal de que o DHCP não respondeu; o DNS não atribui endereço.", 0.85)]),
 ("A21", "E12", 242, "300", False, [("conceito", "int", "uint8_t vai só até 255; o contador estoura e mostra 300 mod 256 = 44.", 0.9)]),
 ("A22", "E12", 12, "44, porque o uint8_t volta a zero depois de 255", True, []),
 ("A23", "E13", 96, "Aumentar a frequência do loop para ler o botão mais vezes", False, [("conceito", "deb", "Ler mais rápido captura ainda mais repiques; é preciso ignorar as bordas por alguns milissegundos.", 0.75)]),
 ("A24", "E14", 386, "Não tem problema, a ISR pode fazer qualquer coisa", False, [("conceito", "isr", "Ignorou que delay() não avança dentro da ISR e que a rotina precisa ser curta.", 0.85)]),
 ("A25", "E10", 2, "UDP, porque um quadro atrasado já não serve", True, []),
]
PENDING_UNDER_H = 100  # erros mais novos que isso ainda esperam a validação do aluno
DECISION_DELAY_H = 3

# sessões de revisão (horas atrás, [(conceito, categoria, nota)])
SESSIONS = [
 ("S1", 212, [("ohm", "unidade", "good"), ("div", "conceito", "again"), ("pot", "procedimento", "good")]),
 ("S2", 120, [("sub", "calculo", "hard"), ("pid", "conceito", "again"), ("odo", "conceito", "good"), ("tcp", "conceito", "good")]),
 ("S3", 28, [("pid", "conceito", "good"), ("div", "conceito", "good"), ("int", "conceito", "easy"), ("pwm", "interpretacao", "good")]),
]

NOTES = [  # (horas atrás, matéria, o que errou, regra, tipo, revisada)
 (600, "Eletrônica", "Corrente em mA na Lei de Ohm", "Antes de dividir, passo mA para A: 15 mA = 0,015 A. Se o resistor der menos de 1 Ω para um LED, a unidade está errada.", "calculo", True),
 (470, "Eletrônica", "Divisor de tensão invertido", "A saída é a tensão sobre o resistor de BAIXO: Vout = Vin × Rbaixo ÷ (Rcima + Rbaixo). Desenho o circuito e marco onde o ADC está ligado.", "conceitual", True),
 (540, "Robótica", "Ki não amortece oscilação", "Oscilação crescente: primeiro baixo o Kp, depois coloco Kd. O Ki só corrige erro que sobra parado (regime).", "conceitual", False),
 (350, "Robótica", "Diâmetro x raio na odometria", "Distância por volta = π × diâmetro (ou 2π × raio). Confiro se o número que o enunciado dá é diâmetro ou raio.", "atencao", True),
 (440, "Redes de computadores", "Broadcast e hosts na /26", "Hosts = 2^(32 − prefixo) − 2. O broadcast é o último endereço do bloco (.63 na /26 que começa em .0), nunca o .255 da /24.", "calculo", False),
 (140, "Redes de computadores", "169.254 é falha de DHCP", "IP 169.254.x.x = APIPA = o DHCP não respondeu. Verifico o servidor DHCP e o cabo antes de pensar em DNS.", "interpretacao", False),
 (230, "Programação", "Overflow em uint8_t", "Escolho o tipo pelo maior valor possível: contador de encoder vai em uint32_t. uint8_t para em 255.", "conceitual", True),
 (40, "Programação", "ISR longa demais", "Na ISR só marco uma flag volatile. delay(), Serial e cálculos pesados ficam no loop.", "conceitual", False),
]

QB = [  # respostas no banco de questões: (slug, alternativa, horas atrás)
 ("me-ohm-led", "d", 196),
 ("me-ohm-led", "a", 20),
 ("me-byte-decimal", "c", 150),
 ("me-drone-mruv", "b", 60),
]

STUDY = {  # material de estudo por matéria
 "ELE": {
  "summary": {"title": "Eletrônica: Lei de Ohm, divisores e potência",
   "overview": "Nos seus exercícios de LEDs, sensores NTC, motores de passo e reguladores, quase todo cálculo parte de V = R × I e de P = V × I. O que mais derrubou as respostas foi a unidade da corrente e a posição do resistor no divisor.",
   "key_points": ["Converta mA para A antes de usar V = R × I (15 mA = 0,015 A).", "No divisor, Vout = Vin × Rbaixo ÷ (Rcima + Rbaixo).", "Potência da carga = V × I; a fonte fornece P ÷ eficiência.", "Confira a ordem de grandeza: resistor de LED fica na casa das dezenas ou centenas de ohms."],
   "common_mistakes": ["Usar corrente em mA direto na Lei de Ohm (apareceu 3 vezes).", "Colocar o resistor de cima no numerador do divisor.", "Multiplicar pela eficiência em vez de dividir."]},
  "flashcards": [
   {"front": "Quanto é 1200 mA em ampères?", "back": "1,2 A", "concept": "Lei de Ohm"},
   {"front": "Fórmula do divisor de tensão (saída sobre o resistor de baixo)", "back": "Vout = Vin × R2 ÷ (R1 + R2)", "concept": "Divisor de tensão"},
   {"front": "Regulador de 80% entrega 10 W. Quanto a bateria fornece?", "back": "10 ÷ 0,8 = 12,5 W", "concept": "Potência elétrica"},
   {"front": "Resistor para LED: que tensão ele recebe?", "back": "Vfonte − Vled", "concept": "Lei de Ohm"}],
  "quiz": [
   {"prompt": "Um sensor de fim de curso puxa 25 mA de 5 V através de um resistor. Qual resistor?", "options": ["200 Ω", "0,2 Ω", "125 Ω", "5 Ω"], "concept": "Lei de Ohm", "correct_choice": 0, "explanation": "25 mA = 0,025 A; 5 ÷ 0,025 = 200 Ω."},
   {"prompt": "Divisor com R1 = 20 kΩ em cima e R2 = 10 kΩ embaixo, em 9 V. Qual Vout sobre R2?", "options": ["6 V", "4,5 V", "3 V", "9 V"], "concept": "Divisor de tensão", "correct_choice": 2, "explanation": "9 × 10 ÷ 30 = 3 V."},
   {"prompt": "Um módulo de câmera consome 5 V × 0,6 A com regulador de 75%. Quanto a bateria fornece?", "options": ["2,25 W", "3 W", "4 W", "3,75 W"], "concept": "Potência elétrica", "correct_choice": 2, "explanation": "3 W ÷ 0,75 = 4 W."}],
  "hours": 100, "round": [0, 1, 2], "source_count": 7},
 "ROB": {
  "summary": {"title": "Robótica: PID, odometria e tração diferencial",
   "overview": "Seus erros em robótica se concentram em como cada ganho do PID muda o comportamento do robô e em conversões geométricas (diâmetro, raio, sentido de giro).",
   "key_points": ["Kp dá força à correção; em excesso causa overshoot.", "Kd amortece a oscilação reagindo à velocidade do erro.", "Ki elimina erro de regime, mas acumula e pode piorar a oscilação.", "Distância por volta = π × diâmetro.", "ω = (vD − vE) ÷ L; positivo = giro anti-horário."],
   "common_mistakes": ["Aumentar Kp ou Ki para conter oscilação.", "Usar o diâmetro no lugar do raio.", "Inverter vD e vE no cálculo de ω."]},
  "flashcards": [
   {"front": "O robô oscila cada vez mais em torno da linha. Primeiro ajuste?", "back": "Diminuir Kp e acrescentar Kd", "concept": "Controle PID"},
   {"front": "Roda de 7 cm de diâmetro: quanto anda por volta?", "back": "π × 7 ≈ 22 cm", "concept": "Odometria"},
   {"front": "PWM 8 bits para 25% de duty", "back": "≈ 64", "concept": "PWM de motores"}],
  "quiz": [
   {"prompt": "O braço robótico para um pouco antes do alvo e fica parado ali. Qual termo do PID resolve?", "options": ["Kd", "Ki", "Reduzir Kp", "Nenhum"], "concept": "Controle PID", "correct_choice": 1, "explanation": "Erro de regime persistente é tarefa do integral."},
   {"prompt": "Encoder de 20 pulsos/volta, roda de 10 cm de diâmetro. Pulsos em 1 m?", "options": ["32", "64", "200", "100"], "concept": "Odometria", "correct_choice": 1, "explanation": "Volta = 31,4 cm; 100 ÷ 31,4 ≈ 3,18 voltas × 20 ≈ 64."}],
  "hours": 30, "round": [1, 1], "source_count": 6},
}

out = []
w = out.append
w("-- Gerado por gerar_seed.py. Troque __USER_ID__ pelo id da conta (auth.users.id).")
w("-- Histórico de demonstração (mmdemo): matérias, exercícios, tentativas, análises,")
w("-- erros, revisões, caderno, material de estudo e banco de questões.")
w("do $seed$")
w("declare")
w("  uid constant uuid := '__USER_ID__';")
w("  t0 constant timestamptz := now();")
w("  v uuid; qrow record; att uuid; ex uuid; subj uuid; conc uuid; diag jsonb; cat text; ans text; ok boolean; an jsonb;")
w("begin")
w("  if not exists (select 1 from auth.users where id = uid) then raise exception 'conta % não existe', uid; end if;")
w(f"  if exists (select 1 from public.attempts where id = '{uid('att:A1')}') then raise exception 'seed já aplicado nesta base'; end if;")
w("  create temp table mm_map(k text primary key, id uuid not null) on commit drop;")
# subjects: reaproveita matéria com mesmo nome
for k, name in SUBJECTS.items():
    w(f"  select id into v from public.subjects where user_id = uid and lower(btrim(name)) = lower({q(name)}) order by created_at limit 1;")
    w(f"  if v is null then insert into public.subjects(id,user_id,name,description,created_at) values('{uid('subj:'+k)}',uid,{q(name)},{q(MARK)},{ago(700)}) returning id into v; end if;")
    w(f"  insert into mm_map values('S:{k}', v);")
for k, (s, name, imp) in CONCEPTS.items():
    w(f"  select id into v from public.concepts where subject_id = (select id from mm_map where k='S:{s}') and lower(name) = lower({q(name)}) order by created_at limit 1;")
    w(f"  if v is null then insert into public.concepts(id,subject_id,name,importance,created_at) values('{uid('conc:'+k)}',(select id from mm_map where k='S:{s}'),{q(name)},{imp},{ago(690)}) returning id into v; end if;")
    w(f"  insert into mm_map values('C:{k}', v);")
for a, b, rel in EDGES:
    w(f"  insert into public.concept_edges(id,from_concept_id,to_concept_id,relation) values('{uid('edge:'+a+b)}',(select id from mm_map where k='C:{a}'),(select id from mm_map where k='C:{b}'),{q(rel)}) on conflict do nothing;")

first_attempt = {}
for a, e, h, *_ in AT:
    first_attempt[e] = max(first_attempt.get(e, 0), h)
for e, (s, diff, prompt, gab, expl, concs) in EX.items():
    w(f"  insert into public.exercises(id,subject_id,source,prompt_text,difficulty,focus_concept,created_at) values('{uid('ex:'+e)}',(select id from mm_map where k='S:{s}'),'manual',{q(prompt)},{q(diff)},{q(CONCEPTS[concs[0]][1])},{ago(first_attempt[e]+2)});")
    for c in concs:
        w(f"  insert into public.exercise_concepts(exercise_id,concept_id) values('{uid('ex:'+e)}',(select id from mm_map where k='C:{c}')) on conflict do nothing;")

events = {}  # (concept, category) -> list of (hours, event_id, attempt_id, prompt, evidence)
for a, e, h, answer, correct, errs in AT:
    s, diff, prompt, gab, expl, concs = EX[e]
    aid = uid("att:" + a)
    names = [CONCEPTS[c][1] for c in concs]
    analysis = {"is_correct": correct, "correct_answer": gab, "explanation": expl,
                "transcribed_prompt": prompt, "transcribed_answer": answer,
                "errors": [{"category": cat, "concept": CONCEPTS[c][1], "evidence": ev, "confidence": cf} for cat, c, ev, cf in errs],
                "concepts": names}
    w(f"  insert into public.attempts(id,exercise_id,user_id,answer,solution_text,attempted_at,status) values('{aid}','{uid('ex:'+e)}',uid,{q(answer)},{q(answer)},{ago(h)},'completed');")
    w(f"  insert into public.attempt_analyses(attempt_id,user_id,subject_id,analysis,model,pipeline_version,created_at) values('{aid}',uid,(select id from mm_map where k='S:{s}'),{js(analysis)},'gemini-2.5-flash','gemini-analysis-v1',{ago(h-0.02)});")
    w(f"  insert into public.corrections(attempt_id,reference_text,created_at) values('{aid}',{q(gab + chr(10)*2 + expl)},{ago(h-0.02)});")
    for i, (cat, c, ev, cf) in enumerate(errs):
        eid = uid(f"ee:{a}:{i}")
        status = "pending" if h < PENDING_UNDER_H else "confirmed"
        w(f"  insert into public.error_events(id,attempt_id,error_type_id,concept_id,evidence_ref,confidence,status,created_at) values('{eid}','{aid}',(select id from public.error_types where name={q(cat)}),(select id from mm_map where k='C:{c}'),{q(ev)},{cf},'{status}',{ago(h-0.02)});")
        if status == "confirmed":
            w(f"  insert into public.error_event_decisions(id,user_id,error_event_id,decision,category,importance,created_at) values('{uid('dec:'+eid)}',uid,'{eid}','confirmed',{q(cat)},{CONCEPTS[c][2]},{ago(h-DECISION_DELAY_H)});")
            events.setdefault((c, cat), []).append((h, eid, aid, prompt, ev))
    if correct:
        for c in concs:
            w(f"  insert into public.mastery_events(id,concept_id,attempt_id,outcome,created_at) values('{uid('me:'+a+c)}',(select id from mm_map where k='C:{c}'),'{aid}','ai_suggested_correct',{ago(h-0.02)});")

# agenda de revisão: simula mm-intervals-v1
def schedule(interval, reps, lapses, rating):
    import math
    prev = max(0, min(180, interval))
    if rating == "again":
        d = 1
    elif rating == "hard":
        d = max(1, math.ceil(prev * 1.2))
    elif rating == "easy":
        d = max(3, math.ceil(prev * 2.5))
    else:
        d = max(1, math.ceil(prev * 2) if prev else 1)
    return min(180, d), reps + 1, lapses + (rating == "again")

items = {}
for key, evs in events.items():
    evs.sort()
    oldest, newest = evs[0], evs[-1]  # newest = menor hora (mais recente)
    created_h = evs[-1][0] - DECISION_DELAY_H if False else max(e[0] for e in evs) - DECISION_DELAY_H
    items[key] = {"id": uid(f"ri:{key[0]}:{key[1]}"), "event": min(evs)[1:], "created_h": created_h,
                  "interval": 0, "reps": 0, "lapses": 0, "last": None, "due_h": created_h}
sess_sql = []
for sid, h, revs in SESSIONS:
    sess = uid("sess:" + sid)
    minutes = 15 if len(revs) <= 3 else 20
    w(f"  insert into public.study_sessions(id,user_id,status,planned_minutes,started_at,completed_at) values('{sess}',uid,'completed',{minutes},{ago(h)},{ago(h - 0.25)});")
    for pos, (c, cat, rating) in enumerate(revs):
        it = items[(c, cat)]
        eid, aid, prompt, ev = it["event"]
        w(f"  insert into public.study_session_items(session_id,item_id,user_id,position,source_attempt_id,source_error_event_id,prompt_text,evidence,category) values('{sess}','{it['id']}',uid,{pos},'{aid}','{eid}',{q(prompt)},{q(ev)},{q(cat)});")
        ans_h = h - 0.03 * (pos + 1)
        it["interval"], it["reps"], it["lapses"] = schedule(it["interval"], it["reps"], it["lapses"], rating)
        it["last"] = ans_h
        it["due_h"] = ans_h - 24 * it["interval"]
        ph = hashlib.sha256(f"{sess}:{it['id']}:{rating}".encode()).hexdigest()
        sess_sql.append(f"  insert into public.review_events(user_id,event_id,session_id,item_id,rating,answered_at,elapsed_seconds,payload_hash,next_due_at) values(uid,'{uid('rev:'+sid+c+cat)}','{sess}','{it['id']}','{rating}',{ago(ans_h)},{40 + 17 * pos},'{ph}',{ago(it['due_h'])});")
# itens precisam existir antes das sessões: reordena
item_sql = []
for (c, cat), it in items.items():
    eid = it["event"][0]
    last = ago(it["last"]) if it["last"] is not None else "null"
    item_sql.append(f"  insert into public.review_items(id,user_id,subject_id,concept_id,error_event_id,category,due_at,interval_days,repetitions,lapses,last_reviewed_at,created_at,updated_at) values('{it['id']}',uid,(select id from mm_map where k='S:{CONCEPTS[c][0]}'),(select id from mm_map where k='C:{c}'),'{eid}',{q(cat)},{ago(it['due_h'])},{it['interval']},{it['reps']},{it['lapses']},{last},{ago(it['created_h'])},{ago(it['last'] if it['last'] is not None else it['created_h'])});")
# move inserts de sessão para depois dos itens
idx = next(i for i, l in enumerate(out) if "insert into public.study_sessions" in l)
sess_block = out[idx:]
del out[idx:]
out.extend(item_sql)
out.extend(sess_block)
out.extend(sess_sql)

w("  insert into public.study_profiles(user_id,stage,daily_minutes,timezone,subject_ids,goal,exam_date,updated_at)")
w("    values(uid,'superior',20,'America/Sao_Paulo',array[(select id from mm_map where k='S:ELE'),(select id from mm_map where k='S:ROB'),(select id from mm_map where k='S:RED'),(select id from mm_map where k='S:PRG')],"
  "'Chegar bem na prova de Sistemas Embarcados e na competição de robótica',(t0 + interval '24 days')::date,t0) on conflict (user_id) do nothing;")

for i, (h, subj, title, rule, typ, rev) in enumerate(NOTES):
    w(f"  insert into public.error_notes(id,user_id,subject,title,description,error_type,reviewed,created_at,updated_at) values('{uid('note:'+str(i))}',uid,{q(subj)},{q(title)},{q(rule)},'{typ}',{str(rev).lower()},{ago(h)},{ago(h - (30 if rev else 0))});")

for s, m in STUDY.items():
    mid = uid("mat:" + s)
    pub, keys = [], []
    for i, qq in enumerate(m["quiz"]):
        qid = uid(f"quiz:{s}:{i}")
        pub.append({"id": qid, "prompt": qq["prompt"], "options": qq["options"], "concept": qq["concept"]})
        keys.append({"id": qid, "correct_choice": qq["correct_choice"], "explanation": qq["explanation"]})
    w(f"  insert into public.study_materials(id,user_id,subject_id,summary,flashcards,quiz,source_count,model,created_at) values('{mid}',uid,(select id from mm_map where k='S:{s}'),{js(m['summary'])},{js(m['flashcards'])},{js(pub)},{m['source_count']},'gemini-2.5-flash',{ago(m['hours'])});")
    w(f"  insert into public.study_quiz_keys(material_id,answers) values('{mid}',{js(keys)});")
    results = [{"question_id": k["id"], "choice": ch, "correct_choice": k["correct_choice"], "is_correct": ch == k["correct_choice"], "explanation": k["explanation"]} for k, ch in zip(keys, m["round"])]
    w(f"  insert into public.study_quiz_rounds(id,material_id,user_id,answers,correct_count,total,created_at) values('{uid('round:'+s)}','{mid}',uid,{js(results)},{sum(r['is_correct'] for r in results)},{len(results)},{ago(m['hours'] - 0.3)});")

# banco de questões: replica question_bank_service.saveObjective (múltipla escolha)
for i, (slug, choice, h) in enumerate(QB):
    aid = uid(f"qb:{i}")
    w(f"""  select b.*, k.answer as key_answer, k.correct_answer, k.explanation into qrow
    from public.question_bank b join public.question_bank_keys k on k.question_id = b.id where b.slug = {q(slug)};
  if qrow.id is not null then
    select id into subj from public.subjects where user_id = uid and lower(btrim(name)) = lower(qrow.subject) order by created_at limit 1;
    if subj is null then insert into public.subjects(id,user_id,name,description,created_at) values('{uid('qbsubj:'+slug)}',uid,qrow.subject,{q(MARK)},{ago(h+1)}) returning id into subj; end if;
    select e.id into ex from public.exercises e where e.subject_id = subj and e.question_id = qrow.id order by e.created_at limit 1;
    if ex is null then
      insert into public.exercises(id,subject_id,source,prompt_text,difficulty,focus_concept,question_id,created_at)
      values('{uid('qbex:'+slug)}',subj,'question_bank',
        qrow.prompt_text || E'\\n\\nAlternativas:' || (select string_agg(E'\\n' || (o->>'id') || ') ' || (o->>'text'), '' order by n) from jsonb_array_elements(qrow.payload->'options') with ordinality as t(o,n)),
        qrow.difficulty, qrow.theme, qrow.id, {ago(h+0.5)}) returning id into ex;
    end if;
    select (o->>'id') || ') ' || (o->>'text') into ans from jsonb_array_elements(qrow.payload->'options') o where o->>'id' = {q(choice)};
    ok := {q(choice)} = qrow.key_answer->>'correct';
    diag := qrow.key_answer->'diagnosis'->{q(choice)};
    an := jsonb_build_object('is_correct', ok, 'correct_answer', qrow.correct_answer, 'explanation', qrow.explanation,
      'transcribed_prompt', (select prompt_text from public.exercises where id = ex), 'transcribed_answer', ans,
      'concepts', jsonb_build_array(left(btrim(qrow.theme),120)),
      'errors', case when ok then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
        'category', coalesce(diag->>'category', qrow.error_category), 'concept', left(btrim(qrow.theme),120),
        'evidence', coalesce(diag->>'feedback', 'Resposta dada: ' || ans || '. Resposta correta: ' || qrow.correct_answer || '.'),
        'confidence', case when diag ? 'feedback' then 0.7 else 0.5 end)) end);
    insert into public.attempts(id,exercise_id,user_id,answer,solution_text,attempted_at,status) values('{aid}',ex,uid,ans,ans,{ago(h)},'completed');
    insert into public.attempt_analyses(attempt_id,user_id,subject_id,analysis,model,pipeline_version,created_at) values('{aid}',uid,subj,an,'gabarito-revisado','question-bank-v1',{ago(h)});
    insert into public.corrections(attempt_id,reference_text,created_at) values('{aid}',qrow.correct_answer || E'\\n\\n' || qrow.explanation,{ago(h)});
    select id into conc from public.concepts where subject_id = subj and lower(name) = lower(left(btrim(qrow.theme),120)) order by created_at limit 1;
    if conc is null then insert into public.concepts(id,subject_id,name,created_at) values('{uid('qbconc:'+slug)}',subj,left(btrim(qrow.theme),120),{ago(h)}) returning id into conc; end if;
    insert into public.exercise_concepts(exercise_id,concept_id) values(ex,conc) on conflict do nothing;
    if not ok then
      insert into public.error_events(id,attempt_id,error_type_id,concept_id,evidence_ref,confidence,status,created_at)
      select '{uid('qbee:'+str(i))}','{aid}',et.id,conc,an->'errors'->0->>'evidence',(an->'errors'->0->>'confidence')::numeric,'pending',{ago(h)}
      from public.error_types et where et.name = an->'errors'->0->>'category';
    else
      insert into public.mastery_events(id,concept_id,attempt_id,outcome,created_at) values('{uid('qbme:'+str(i))}',conc,'{aid}','question_bank_correct',{ago(h)});
    end if;
    insert into public.question_responses(id,user_id,question_id,attempt_id,response,is_correct,score,created_at)
      values('{uid('qbr:'+str(i))}',uid,qrow.id,'{aid}',jsonb_build_object('choice',{q(choice)}),ok,case when ok then 1 else 0 end,{ago(h)});
  end if;""")
w("end")
w("$seed$;")

base = pathlib.Path(__file__).parent
tag = USER[:8]
(base / f"seed-{tag}.sql").write_text("\n".join(out).replace("__USER_ID__", USER) + "\n", encoding="utf-8")

# remoção: só o que tem id determinístico deste seed
ids = lambda prefix, keys: ",".join(f"'{uid(prefix + k)}'" for k in keys)
att_ids = [uid("att:" + a[0]) for a in AT] + [uid(f"qb:{i}") for i in range(len(QB))]
rm = ["-- Remove o histórico de demonstração (mmdemo). Troque __USER_ID__.",
 "begin;",
 f"delete from public.study_sessions where user_id = '__USER_ID__' and id in ({ids('sess:', [s[0] for s in SESSIONS])});",
 f"delete from public.review_items where user_id = '__USER_ID__' and id in ({','.join(repr(it['id']).replace(chr(34), chr(39)) for it in items.values())});",
 f"delete from public.study_materials where user_id = '__USER_ID__' and id in ({ids('mat:', list(STUDY))});",
 f"delete from public.question_responses where user_id = '__USER_ID__' and id in ({ids('qbr:', [str(i) for i in range(len(QB))])});",
 f"delete from public.attempts where user_id = '__USER_ID__' and id in ({','.join(repr(x).replace(chr(34), chr(39)) for x in att_ids)});",
 f"delete from public.exercises where id in ({ids('ex:', list(EX))},{ids('qbex:', [s for s, _, _ in QB])});",
 f"delete from public.concepts where id in ({ids('conc:', list(CONCEPTS))},{ids('qbconc:', [s for s, _, _ in QB])}) and not exists (select 1 from public.exercise_concepts ec where ec.concept_id = concepts.id);",
 f"delete from public.subjects where user_id = '__USER_ID__' and id in ({ids('subj:', list(SUBJECTS))},{ids('qbsubj:', [s for s, _, _ in QB])}) and not exists (select 1 from public.exercises e where e.subject_id = subjects.id);",
 f"update public.error_notes set deleted_at = now(), updated_at = now() where user_id = '__USER_ID__' and deleted_at is null and id in ({ids('note:', [str(i) for i in range(len(NOTES))])});",
 "commit;"]
(base / f"remover-{tag}.sql").write_text("\n".join(rm).replace("__USER_ID__", USER) + "\n", encoding="utf-8")
print("ok", len(out), "linhas;", len(items), "itens de revisão")
