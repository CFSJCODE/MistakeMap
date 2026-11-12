# C4 — Contexto do MistakeMap

```mermaid
C4Context
    title Contexto do sistema MistakeMap

    Person(student, "Estudante", "Registra exercícios e resoluções, consulta padrões e pratica.")
    Person(admin, "Administrador", "Acompanha métricas operacionais e configuração do sistema.")

    System(app, "MistakeMap", "Cliente Flutter para Android, Windows e Web; registra exercícios, apresenta mapa e prática.")
    System_Ext(supabase, "Supabase", "Auth, PostgreSQL com RLS, Realtime e Edge Functions Deno.")
    System_Ext(gemini, "Google Gemini", "Análise multimodal, classificação pedagógica e geração estruturada de prática.")
    System_Ext(r2, "Cloudflare R2", "Armazena imagens enviadas por URLs pré-assinadas.")
    System_Ext(vercel, "Vercel", "Hospeda a versão Web publicada.")
    System_Ext(github, "GitHub Actions", "Executa CI e publica funções, migrations e aplicação Web.")

    Rel(student, app, "Usa", "Flutter UI")
    Rel(admin, app, "Consulta métricas", "Flutter UI")
    Rel(app, supabase, "Autentica, consulta dados e recebe eventos", "HTTPS / Supabase SDK")
    Rel(app, r2, "Envia fotos usando URL assinada", "HTTPS PUT")
    Rel(supabase, gemini, "Analisa tentativas e gera prática", "HTTPS REST / JSON estruturado")
    Rel(supabase, r2, "Lê imagens para análise", "S3 API")
    Rel(github, supabase, "Publica Edge Functions e migrations após checks", "Supabase CLI")
    Rel(github, vercel, "Compila e publica Flutter Web", "Vercel CLI")
```

## Observações

- O sistema de produto inclui o cliente Flutter; Supabase, Gemini, R2, Vercel e
  GitHub Actions são plataformas externas ou serviços integrados.
- O SQLite e a fila offline são internos ao cliente Flutter e não foram
  representados como sistema externo.
- O worker Rust não aparece como sistema ativo: está arquivado e não participa
  dos fluxos atuais.
- `/health` é público e não expõe dados acadêmicos. Operações de análise e
  prática exigem autenticação validada no backend; o job de lote usa segredo
  próprio de cron.
- O diagrama descreve o código e a configuração versionados; não confirma a
  topologia exata atualmente implantada em produção.
