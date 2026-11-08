import type { Database } from "./ai_service.ts";
import { CATEGORIES, PublicError } from "./ai_contract.ts";
import {
  id,
  type Input,
  integer,
  materialUrl,
  optionalId,
  text,
} from "./platform_contract.ts";

const missing = () =>
  new PublicError(
    404,
    "draft_not_found",
    "Rascunho não encontrado ou indisponível para edição.",
  );
export function contentInput(input: Input) {
  if (input.rights_confirmed !== true) {
    throw new PublicError(
      400,
      "rights_required",
      "Confirme a autoria ou autorização para publicar o conteúdo e a explicação.",
    );
  }
  const subject = text(input, "subject", 120),
    topic = text(input, "topic", 120),
    theme = text(input, "theme", 120);
  const position = integer(input, "position", 1, 5),
    difficulty = text(input, "difficulty", 10),
    category = text(input, "error_category", 20);
  const prompt = text(input, "prompt_text", 5000),
    answer = text(input, "correct_answer", 2000),
    explanation = text(input, "explanation", 5000),
    technology = text(input, "technology_context", 1000);
  if (
    !["facil", "media", "dificil"].includes(difficulty) ||
    !CATEGORIES.includes(category as typeof CATEGORIES[number])
  ) {
    throw new PublicError(
      400,
      "invalid_content_category",
      "Escolha dificuldade e categoria válidas.",
    );
  }
  if (prompt.length < 20 || explanation.length < 10 || technology.length < 20) {
    throw new PublicError(
      400,
      "content_too_short",
      "Detalhe o enunciado, a explicação e a função do sistema tecnológico no problema.",
    );
  }
  // Uma triagem lexical não substitui revisão pedagógica; impede publicar
  // enunciados evidentemente alheios ao recorte antes da revisão humana.
  if (
    !/(rob[oô]|circuit|sensor|processador|computador|program|software|hardware|rede|eletr[oô]|el[eé]tric|automa|energia|bateria|drone|algorit|microcontrol|motor|servidor|tecnolog|digital|mem[oó]ria|dispositivo|m[aá]quina)/iu
      .test(prompt)
  ) {
    throw new PublicError(
      400,
      "technology_required",
      "O dispositivo ou sistema tecnológico precisa participar do enunciado e fornecer os dados do problema.",
    );
  }
  const source = text(input, "source_url", 2000, true);
  return {
    subject,
    topic,
    theme,
    position,
    difficulty,
    category,
    prompt,
    answer,
    explanation,
    technology,
    source: source ? materialUrl({ url: source }) : null,
  };
}

export async function contentOperation(
  sql: Database,
  user: string,
  input: Input,
  action: string,
) {
  const [profile] =
    await sql`SELECT role FROM public.profiles WHERE id=${user}`;
  const admin = profile?.role === "admin";
  const teachers =
    await sql`SELECT 1 FROM public.platform_teachers WHERE user_id=${user}`;
  if (!admin && !teachers.length) {
    throw new PublicError(
      403,
      "editor_required",
      "A edição de conteúdo está disponível para professores habilitados e administradores.",
    );
  }
  if (action === "content_drafts") {
    const drafts =
      await sql`SELECT * FROM public.platform_content_drafts WHERE (${admin} OR author_id=${user}) ORDER BY updated_at DESC LIMIT 100`;
    return { drafts, can_publish: admin, limit: 100 };
  }
  const draftId = optionalId(input, "id");
  if (action === "save_content_draft") {
    const d = contentInput(input);
    if (draftId) {
      const [draft] =
        await sql`UPDATE public.platform_content_drafts SET subject=${d.subject},topic=${d.topic},theme=${d.theme},position=${d.position},difficulty=${d.difficulty},error_category=${d.category},prompt_text=${d.prompt},correct_answer=${d.answer},explanation=${d.explanation},technology_context=${d.technology},source_url=${d.source},rights_confirmed_at=now(),status='draft',review_note='',reviewed_at=NULL,reviewed_by=NULL,updated_at=now()
        WHERE id=${draftId} AND author_id=${user} AND status<>'published' RETURNING *`;
      if (!draft) throw missing();
      return { draft };
    }
    const [draft] =
      await sql`INSERT INTO public.platform_content_drafts(author_id,subject,topic,theme,position,difficulty,error_category,prompt_text,correct_answer,explanation,technology_context,source_url)
      VALUES(${user},${d.subject},${d.topic},${d.theme},${d.position},${d.difficulty},${d.category},${d.prompt},${d.answer},${d.explanation},${d.technology},${d.source}) RETURNING *`;
    return { draft };
  }
  const target = id(input, "id");
  if (action === "submit_content_draft") {
    const [draft] =
      await sql`UPDATE public.platform_content_drafts SET status='pending_review',review_note='',updated_at=now() WHERE id=${target} AND author_id=${user} AND status IN ('draft','rejected') RETURNING *`;
    if (!draft) throw missing();
    return { draft };
  }
  if (!admin) {
    throw new PublicError(
      403,
      "admin_required",
      "Somente a administração pode revisar e publicar o catálogo.",
    );
  }
  const note = text(input, "review_note", 2000);
  if (action === "reject_content_draft") {
    const [draft] =
      await sql`UPDATE public.platform_content_drafts SET status='rejected',review_note=${note},reviewed_by=${user},reviewed_at=now(),updated_at=now() WHERE id=${target} AND status='pending_review' RETURNING *`;
    if (!draft) throw missing();
    return { draft };
  }
  if (input.answer_verified !== true || input.technology_confirmed !== true) {
    throw new PublicError(
      400,
      "review_required",
      "Confirme explicitamente que resolveu a questão, verificou o gabarito e revisou a temática de tecnologia.",
    );
  }
  return await sql.begin(async (tx) => {
    const [draft] =
      await tx`SELECT * FROM public.platform_content_drafts WHERE id=${target} FOR UPDATE`;
    if (!draft) throw missing();
    if (draft.status === "published") return { draft, already_published: true };
    if (draft.status !== "pending_review") {
      throw new PublicError(
        409,
        "draft_not_submitted",
        "Envie o rascunho para revisão antes de publicar.",
      );
    }
    const [published] =
      await tx`INSERT INTO public.catalog_exercises(subject,topic,theme,position,difficulty,error_category,prompt_text,reviewed_at,reviewed_by)
      VALUES(${draft.subject},${draft.topic},${draft.theme},${draft.position},${draft.difficulty},${draft.error_category},${draft.prompt_text},now(),'Equipe editorial MistakeMap')
      ON CONFLICT(subject,topic,theme,position) DO UPDATE SET difficulty=EXCLUDED.difficulty,error_category=EXCLUDED.error_category,prompt_text=EXCLUDED.prompt_text,reviewed_at=EXCLUDED.reviewed_at,reviewed_by=EXCLUDED.reviewed_by RETURNING id`;
    await tx`INSERT INTO public.catalog_answer_keys(catalog_exercise_id,correct_answer,explanation) VALUES(${published.id},${draft.correct_answer},${draft.explanation}) ON CONFLICT(catalog_exercise_id) DO UPDATE SET correct_answer=EXCLUDED.correct_answer,explanation=EXCLUDED.explanation`;
    const [updated] =
      await tx`UPDATE public.platform_content_drafts SET status='published',review_note=${note},reviewed_by=${user},reviewed_at=now(),catalog_exercise_id=${published.id},updated_at=now() WHERE id=${target} RETURNING *`;
    // Sessões já abertas têm snapshots e não mudam com a publicação.
    return { draft: updated, catalog_exercise_id: published.id };
  });
}
