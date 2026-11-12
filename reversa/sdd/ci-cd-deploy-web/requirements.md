# CI/CD e deploy Web

## Visão Geral

Esta unit valida as stacks Flutter, Deno e Rust em CI, publica Edge Functions/migrations no Supabase e compila Flutter Web para Vercel. O worker Rust permanece legado, mas ainda participa dos checks. 🟢

## Responsabilidades

- Executar análise, formatação e testes Flutter. 🟢
- Executar `deno check` e testes das Edge Functions. 🟢
- Executar check, Clippy e testes do worker Rust. 🟢
- Publicar funções Supabase após gate Deno e migrations após dry-run. 🟢
- Publicar Flutter Web em produção via Vercel. 🟢
- Gerar entregáveis Android/Windows em workflow automatizado. 🔴

## Regras de Negócio

- Deploy de funções parte de `main` e depende de gate de testes Deno. 🟢
- Deploy de migrations verifica conteúdo, executa dry-run e então aplica; histórico não deve ser reescrito. 🟢
- Deploy Web usa secrets Vercel; valores não devem ser incluídos em código. 🟢
- Não foram encontrados workflows de build/publicação Android ou Windows. 🟢
- A publicação do worker Fly.io é referência antiga e não deve ser considerada produção atual. 🟢

## Requisitos Funcionais

| ID | Requisito | Prioridade | Critério de Aceite |
|---|---|---|---|
| RF-01 | Rodar checks Flutter, Deno e Rust em PR/push configurado. 🟢 | Must | PR recebe resultado dos três gates. |
| RF-02 | Publicar Edge Functions após checks Deno no branch autorizado. 🟢 | Must | Deploy não ocorre quando teste/check falha. |
| RF-03 | Fazer dry-run de migrations antes de push ao Supabase. 🟢 | Must | Diff é verificado antes da aplicação. |
| RF-04 | Construir Flutter Web release e publicar via Vercel. 🟢 | Should | Deploy usa secrets e só aciona por mudanças elegíveis. |
| RF-05 | Gerar APK e instalador Windows de forma automatizada. 🔴 | Could | Não existe workflow confirmado e o formato/canal de entrega precisa ser definido. |
| RF-06 | Manter worker Rust como backend em produção. 🔴 | Won't | Está arquivado e não é o fluxo ativo. |

## Requisitos Não Funcionais

| Tipo | Requisito inferido | Evidência no código | Confiança |
|---|---|---|---|
| Segurança | Credenciais de deploy são armazenadas em secrets, não no repositório. | `.github/workflows/supabase-functions-deploy.yml`, `.github/workflows/web-deploy-vercel.yml` | 🟢 |
| Integridade | Migration é submetida a dry-run e deploy serializado. | `.github/workflows/supabase-deploy.yml` | 🟢 |
| Qualidade | Flutter/Deno/Rust têm versões fixadas e gates de lint/teste. | `.github/workflows/ci.yml` | 🟢 |

## Critérios de Aceitação

```gherkin
Dado um pull request com mudança Flutter
Quando CI executa
Então flutter analyze, format e test devem fornecer resultado

Dado um pull request com mudança de função
Quando CI executa
Então deno check e deno test devem fornecer resultado

Dado uma migration alterada no branch principal
Quando o workflow de banco executa
Então faz dry-run antes do db push

Dado que um gate obrigatório falhou
Quando o deploy é avaliado
Então a publicação correspondente não ocorre

Dado uma alteração do cliente Web que passou nos gates
Quando o workflow Vercel executa
Então compila Flutter Web release e publica usando secrets

Dado que a equipe precisa de APK e Windows instalável
Quando consulta os workflows existentes
Então não encontra publicação automatizada dessas plataformas
```

## Prioridade (MoSCoW)

| Requisito | MoSCoW | Justificativa |
|---|---|---|
| Gates de qualidade por stack | Must | Bloqueiam regressões antes de merge/deploy. |
| Deploy seguro de funções e banco | Must | Mantém backend consistente e secrets fora do cliente. |
| Deploy Web | Should | Caminho de distribuição existente. |
| Distribuição Android/Windows | Could | Falta definição de formato/canal e workflow. |
| Deploy do worker arquivado | Won't | Caminho de produção substituído. |

## Rastreabilidade de Código

| Arquivo | Função / Classe | Cobertura |
|---|---|---|
| `.github/workflows/ci.yml` | Checks Flutter, Deno e Rust | 🟢 |
| `.github/workflows/supabase-functions-deploy.yml` | Deploy Edge Functions | 🟢 |
| `.github/workflows/supabase-deploy.yml` | Deploy migrations | 🟢 |
| `.github/workflows/web-deploy-vercel.yml` | Build e deploy Web | 🟢 |
| `supabase/config.toml` | Configuração das funções | 🟢 |
