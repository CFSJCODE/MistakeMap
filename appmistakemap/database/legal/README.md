# Textos legais da escola

Cada documento tem uma pasta e cada versão um arquivo `<versão>.md`. O texto que
o dono da escola aceita no app é o que está no banco (`legal_document_versions`),
copiado daqui por migration. `scripts/verify-school-agreements.sh` confere que o
hash SHA-256 gravado é o mesmo destes arquivos.

| Pasta (chave no banco) | Documento |
|---|---|
| `termos-de-uso` | Termos de Uso do MistakeMap para Escolas |
| `contrato-saas` | Contrato de Prestação de Serviços (SaaS) |
| `acordo-tratamento-dados` | Acordo de Tratamento de Dados Pessoais (escola controladora, MistakeMap operador) |

## Publicar uma versão nova

1. Crie `<pasta>/<versão nova>.md` (ex.: `contrato-saas/1.1.md`). Nunca edite um arquivo já publicado.
2. Gere o INSERT: `python3 scripts/legal_document_sql.py contrato-saas 1.1 2027-01-01` (a data é quando passa a valer).
3. Cole a saída numa migration nova em `appmistakemap/database/supabase/migrations/`.
4. Ajuste o teste de hash em `scripts/school_agreements/tests.sql` se quiser cobrir a versão nova e rode `scripts/verify-school-agreements.sh`.

A partir da data de vigência, toda escola volta a ficar bloqueada até o dono aceitar
a versão nova. Avise as escolas antes (o Acordo de Tratamento de Dados pede 15 dias
para troca de suboperador).

## Antes do primeiro contrato real

- Revisão por advogado dos três textos.
- Dados da empresa (razão social, CNPJ, endereço) na proposta comercial e na nota fiscal; o contrato remete a eles.
- Canal do encarregado (DPO) na página Sobre do app, que os três textos citam.
- Provedores de IA em plano que não usa os dados para treino (o Acordo promete isso; o nível gratuito da API Gemini usa).
