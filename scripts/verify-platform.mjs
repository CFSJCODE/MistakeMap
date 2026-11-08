// Integration checks run exclusively in embedded PostgreSQL. See
// verify-study-review.mjs for the isolated PGLITE_MODULE installation.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { randomUUID } from "node:crypto";
import { bridge, createFixture, projectRoot } from "./verify-study-review.mjs";
import { platformOperation } from "../supabase/functions/_shared/platform_service.ts";

const db = await createFixture();
const sql = bridge(db);
const migration = (name) =>
  readFile(
    resolve(projectRoot, "appmistakemap/database/supabase/migrations", name),
    "utf8",
  );
await db.exec(await migration("20260901173121_create_profiles.sql"));
await db.exec(
  `ALTER TABLE profiles ADD COLUMN role text NOT NULL DEFAULT 'user';
  INSERT INTO error_types(name) VALUES('calculo'),('conceito'),('sinal'),('interpretacao'),('procedimento'),('unidade'),('outro');
  CREATE TABLE practice_answer_keys(exercise_id uuid PRIMARY KEY,correct_answer text,explanation text);
  CREATE TABLE attempt_analyses(attempt_id uuid PRIMARY KEY,user_id uuid,subject_id uuid,analysis jsonb);
  CREATE TABLE practice_sets(id uuid PRIMARY KEY,user_id uuid);
  CREATE TABLE error_notes(id uuid PRIMARY KEY,user_id uuid,title text);
  CREATE TABLE attempt_assets(id uuid PRIMARY KEY,attempt_id uuid,object_path text,sha256 text,created_at timestamptz DEFAULT now());
  CREATE TABLE notebook_entries(id uuid PRIMARY KEY,user_id uuid,titulo text);
`,
);
await db.exec(await migration("20261031221426_study_materials.sql"));
await db.exec(await migration("20261102003100_catalog_exercises.sql"));
await db.exec(await migration("20261102173000_catalog_tecnologia.sql"));
await db.exec(
  await migration("20261106020000_learning_platform_commercial.sql"),
);
await db.exec(
  `CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$ SELECT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND p.role='admin') $$;`,
);
await db.exec(await migration("20261106030000_content_editor.sql"));
await db.exec(await migration("20261106040000_account_lifecycle.sql"));
await db.exec(await migration("20261106060000_teacher_feedback.sql"));
await db.exec(await migration("20261106080000_study_milestones.sql"));
const user = randomUUID(),
  other = randomUUID(),
  teacher = randomUUID(),
  admin = randomUUID();
for (const uid of [user, other, teacher, admin]) {
  await db.query("INSERT INTO auth.users(id) VALUES($1)", [uid]);
  await db.query(
    "INSERT INTO profiles(id,education_level,role) VALUES($1,'ensino_superior',$2)",
    [uid, uid === admin ? "admin" : "user"],
  );
}
const op = (action, input = {}, owner = user) =>
  platformOperation(sql, owner, { action, ...input });
const library = await op("catalog");
assert.equal(library.exercises.length, 30);
assert.ok(!JSON.stringify(library).includes("correct_answer"));
const topic = library.exercises[0];
const anotherSubject =
  library.exercises.find((row) => row.subject !== topic.subject).subject;
const goal = (await op("save_goal", {
  title: "Prova de tecnologia",
  exam_date: "2099-12-01",
  minutes_per_day: 15,
  subjects: [topic.subject, anotherSubject],
})).goal;
assert.equal(goal.weekly_plan.length, 7);
await assert.rejects(
  () =>
    op("save_goal", {
      id: goal.id,
      title: "Tentativa alheia",
      minutes_per_day: 15,
      subjects: [],
    }, other),
  { code: "not_found" },
);
const request_id = randomUUID();
const payload = {
  request_id,
  mode: "exam",
  subject: topic.subject,
  theme: topic.theme,
  count: 2,
  goal_id: goal.id,
};
const exam = (await op("start_session", payload)).session;
assert.equal(exam.items.length, 2);
assert.equal(exam.results, null);
assert.ok(!JSON.stringify(exam).includes("correct_answer"));
assert.equal((await op("start_session", payload)).session.id, exam.id);
assert.equal(
  (await db.query(
    "SELECT count(*)::int AS n FROM platform_sessions WHERE user_id=$1",
    [user],
  )).rows[0].n,
  1,
);
await assert.rejects(() => op("start_session", { ...payload, count: 3 }), {
  code: "request_reused",
});
await assert.rejects(() => op("get_session", { session_id: exam.id }, other), {
  code: "not_found",
});
await assert.rejects(
  () =>
    op("save_answer", {
      session_id: exam.id,
      item_id: exam.items[0].id,
      answer: "anything",
    }, other),
  { code: "not_found" },
);
await assert.rejects(
  () =>
    op("hints", { session_id: exam.id, item_id: exam.items[0].id, level: 3 }),
  { code: "exam_no_hints" },
);
const [correct] =
  await sql`SELECT correct_answer FROM platform_session_keys WHERE item_id=${
    exam.items[0].id
  }`;
await op("save_answer", {
  session_id: exam.id,
  item_id: exam.items[0].id,
  answer: correct.correct_answer,
});
const result = await op("finish_session", { session_id: exam.id });
assert.equal(result.correct_count, 1);
assert.equal(result.results[1].verdict, "unanswered");
assert.equal(
  (await op("finish_session", { session_id: exam.id })).correct_count,
  1,
);
await assert.rejects(
  () =>
    op("save_answer", {
      session_id: exam.id,
      item_id: exam.items[0].id,
      answer: "overwrite",
    }),
  { code: "session_finished" },
);
const practice = (await op("start_session", {
  request_id: randomUUID(),
  mode: "practice",
  count: 1,
})).session;
assert.ok(
  (await op("hints", {
    session_id: practice.id,
    item_id: practice.items[0].id,
    level: 1,
  })).assisted,
);
const finishedPractice = await op("finish_session", {
  session_id: practice.id,
});
assert.equal(finishedPractice.assisted, true);
// Explicit weekly refresh: source is only this student's completed goal
// sessions, and needs_review means uncertainty, never a mastery diagnosis.
const targetTheme = library.exercises.find((row) =>
  goal.subjects.includes(row.subject) && row.theme !== goal.weekly_plan[0].theme
);
const adaptive = (await op("start_session", {
  request_id: randomUUID(),
  mode: "exam",
  subject: targetTheme.subject,
  theme: targetTheme.theme,
  count: 1,
  goal_id: goal.id,
})).session;
await op("save_answer", {
  session_id: adaptive.id,
  item_id: adaptive.items[0].id,
  answer: "Quero conferir meu raciocínio antes de concluir.",
});
await op("finish_session", { session_id: adaptive.id });
await db.query(
  "UPDATE platform_goals SET weekly_plan='[]'::jsonb,updated_at='2000-01-01' WHERE id=$1",
  [goal.id],
);
assert.equal(
  (await op("overview")).goals.find((row) => row.id === goal.id)
    .refresh_recommended,
  true,
  "Stale plans ask for an explicit refresh",
);
await assert.rejects(() => op("refresh_goal", { id: goal.id }, other), {
  code: "not_found",
}, "Another account cannot refresh the goal");
const refreshed = (await op("refresh_goal", { id: goal.id })).goal;
assert.ok(
  refreshed.weekly_plan[0].theme === targetTheme.theme &&
    refreshed.weekly_plan[0].needs_review_count === 1,
  "Recent uncertain responses precede the other catalog themes",
);
assert.deepEqual(
  refreshed.weekly_plan.map((day) => day.date),
  Array.from(
    { length: 7 },
    (_, i) => new Date(Date.now() + i * 86400000).toISOString().slice(0, 10),
  ),
  "Refresh writes the next seven calendar days",
);
assert.ok(
  refreshed.weekly_plan.every((day) => day.minutes === 15) &&
    String(refreshed.exam_date) === String(goal.exam_date) &&
    JSON.stringify(refreshed.subjects) === JSON.stringify(goal.subjects),
  "Daily budget, exam date and subjects are preserved",
);
assert.ok(
  new Date(refreshed.updated_at).getTime() > Date.parse("2000-01-01"),
  "Refresh persists updated_at",
);
assert.equal(
  (await op("overview")).goals.find((row) => row.id === goal.id)
    .refresh_recommended,
  false,
  "Overview does not recompute a fresh plan silently",
);
// Quota blocks new sessions, not resume/export/history, and is read on server.
await db.query(
  "INSERT INTO platform_entitlements(user_id,plan,sessions_per_day) VALUES($1,'pilot',2)",
  [user],
);
await assert.rejects(
  () =>
    op("start_session", {
      request_id: randomUUID(),
      mode: "practice",
      count: 1,
    }),
  { code: "session_limit" },
);
assert.equal(
  (await op("get_session", { session_id: exam.id })).session.status,
  "completed",
);
await assert.rejects(() => op("create_class", { title: "Turma" }), {
  code: "teacher_required",
});
await assert.rejects(() => op("grant_teacher", { user_id: teacher }), {
  code: "access_denied",
});
await op("grant_teacher", { user_id: teacher }, admin);
const classroom =
  (await op("create_class", { title: "Turma de robótica" }, teacher)).class;
await op("join_class", { code: classroom.code });
const overview = await op("overview");
assert.equal(
  overview.classes[0].code,
  null,
  "Learners never get invitation secrets",
);
assert.equal(overview.entitlements.plan, "pilot");
assert.equal(overview.progress.correct, 1);
const assignment = (await op("create_assignment", {
  class_id: classroom.id,
  title: "Lista de treino",
  catalog_ids: [topic.id],
}, teacher)).assignment;
await assert.rejects(
  () =>
    op("create_assignment", {
      class_id: classroom.id,
      title: "Ataque",
      catalog_ids: [topic.id],
    }),
  { code: "access_denied" },
);
await db.query(
  "UPDATE platform_entitlements SET sessions_per_day=10 WHERE user_id=$1",
  [user],
);
const task = (await op("start_session", {
  request_id: randomUUID(),
  mode: "exam",
  assignment_id: assignment.id,
})).session;
await assert.rejects(
  () =>
    op(
      "save_feedback",
      { session_id: task.id, body: "Ainda em andamento." },
      teacher,
    ),
  { code: "feedback_not_authorized" },
);
await op("finish_session", { session_id: task.id });
await assert.rejects(
  () =>
    op(
      "save_feedback",
      { session_id: task.id, body: "Sem permissão." },
      teacher,
    ),
  { code: "feedback_not_authorized" },
);
await op("save_note", {
  title: "Regra para minha revisão",
  body: "Minha regra sobre o circuito",
  concept: topic.theme,
  catalog_exercise_id: topic.id,
});
let shared = await op("class_progress", { class_id: classroom.id }, teacher);
assert.equal(shared.students[0].progress, null);
assert.equal(shared.students[0].answers, null);
assert.equal(shared.students[0].notes, null);
await op("set_sharing", {
  class_id: classroom.id,
  share_progress: true,
  share_answers: true,
  share_notes: true,
});
await assert.rejects(
  () =>
    op("save_feedback", {
      session_id: task.id,
      body: "Autocorreção privilegiada.",
    }),
  { code: "feedback_not_authorized" },
);
await assert.rejects(
  () =>
    op("save_feedback", {
      session_id: task.id,
      body: "Professor de outra turma.",
    }, other),
  { code: "feedback_not_authorized" },
);
const feedback = (await op("save_feedback", {
  session_id: task.id,
  body: "Revise a unidade e escreva sua regra com suas palavras.",
}, teacher)).feedback;
assert.equal(
  (await op("save_feedback", {
    session_id: task.id,
    body: "Feedback atualizado: explique a unidade do circuito.",
  }, teacher)).feedback.id,
  feedback.id,
  "Feedback updates do not duplicate the teacher response",
);
assert.equal(
  (await op("overview")).feedback[0].body,
  "Feedback atualizado: explique a unidade do circuito.",
);
shared = await op("class_progress", { class_id: classroom.id }, teacher);
assert.equal(shared.students[0].progress.sessions, 1);
assert.equal(shared.students[0].answers.length, 1);
assert.equal(shared.students[0].notes.length, 1);
assert.equal(shared.students[0].answers[0].feedback[0].id, feedback.id);
await op("set_sharing", {
  class_id: classroom.id,
  share_progress: false,
  share_answers: false,
  share_notes: false,
});
shared = await op("class_progress", { class_id: classroom.id }, teacher);
assert.equal(
  shared.students[0].answers,
  null,
  "Revocation takes effect on the next report",
);
await assert.rejects(
  () =>
    op(
      "save_feedback",
      { session_id: task.id, body: "Permissão revogada." },
      teacher,
    ),
  { code: "feedback_not_authorized" },
);
assert.equal(
  (await op("overview")).feedback.length,
  1,
  "Student keeps their received feedback after revocation",
);
await op("leave_class", { class_id: classroom.id });
assert.equal(
  (await op("class_progress", { class_id: classroom.id }, teacher)).students
    .length,
  0,
);
await assert.rejects(
  () =>
    op("start_session", {
      request_id: randomUUID(),
      mode: "exam",
      assignment_id: assignment.id,
    }),
  { code: "not_found" },
);
await op("join_class", { code: classroom.code });
await op("rotate_class_code", { class_id: classroom.id }, teacher);
await assert.rejects(() => op("join_class", { code: classroom.code }, other), {
  code: "not_found",
});
await op("save_material", {
  title: "Apostila",
  url: "https://example.com/circuitos.pdf",
  rights_confirmed: true,
  page_number: 4,
});
await assert.rejects(
  () =>
    op("save_material", {
      title: "Sem confirmação",
      url: "https://example.com/a.pdf",
    }),
  { code: "rights_required" },
);
await assert.rejects(() => op("content_drafts"), { code: "editor_required" });
const draftPayload = {
  subject: topic.subject,
  topic: topic.topic,
  theme: topic.theme,
  position: 1,
  difficulty: "facil",
  error_category: "calculo",
  prompt_text:
    "Um sensor digital fornece x + 2 = 5 unidades na calibração. Determine o valor de x para configurar o dispositivo.",
  correct_answer: "x = 3",
  explanation: "Subtraia 2 dos dois lados: x = 5 - 2 = 3.",
  technology_context:
    "O sensor fornece os dados para calibrar o dispositivo digital.",
  rights_confirmed: true,
};
const draft = (await op("save_content_draft", draftPayload, teacher)).draft;
assert.equal(draft.status, "draft");
await assert.rejects(
  () => op("submit_content_draft", { id: draft.id }, admin),
  { code: "draft_not_found" },
);
await op("submit_content_draft", { id: draft.id }, teacher);
await assert.rejects(
  () =>
    op("publish_content_draft", {
      id: draft.id,
      review_note: "Verificada",
      answer_verified: true,
      technology_confirmed: true,
    }, teacher),
  { code: "admin_required" },
);
await op("reject_content_draft", {
  id: draft.id,
  review_note: "Esclareça a unidade do sensor.",
}, admin);
const revised =
  (await op("save_content_draft", { ...draftPayload, id: draft.id }, teacher))
    .draft;
assert.equal(revised.status, "draft");
await op("submit_content_draft", { id: draft.id }, teacher);
await assert.rejects(
  () =>
    op("publish_content_draft", {
      id: draft.id,
      review_note: "Sem confirmação",
    }, admin),
  { code: "review_required" },
);
const publication = await op("publish_content_draft", {
  id: draft.id,
  review_note: "Resolvida, unidade e contexto conferidos.",
  answer_verified: true,
  technology_confirmed: true,
}, admin);
assert.equal(publication.draft.status, "published");
assert.equal(
  (await op("catalog")).exercises.length,
  30,
  "Publishing a revision upserts its existing slot",
);
assert.equal(
  (await db.query(
    "SELECT correct_answer FROM platform_session_keys WHERE item_id=$1",
    [exam.items[0].id],
  )).rows[0].correct_answer,
  correct.correct_answer,
  "Existing snapshot never changes with editorial publication",
);
await assert.rejects(
  () => op("save_content_draft", { ...draftPayload, id: draft.id }, teacher),
  { code: "draft_not_found" },
);
const deletion = await op("request_deletion", {
  confirmation: "EXCLUIR MINHA CONTA",
});
assert.equal(deletion.deleted, false);
assert.equal(deletion.request.status, "pending");
assert.equal(
  (await op("request_deletion", { confirmation: "EXCLUIR MINHA CONTA" }))
    .request.id,
  deletion.request.id,
);
await op("cancel_deletion", { id: deletion.request.id });
const exported = await op("export_data");
await db.query(
  "INSERT INTO study_streak_freezes(user_id,frozen_date,week_start,timezone) VALUES($1,'2026-11-06','2026-11-02','America/Sao_Paulo')",
  [user],
);
for (const table of exported.tables) {
  const page = await op("export_data", { table });
  assert.ok(Array.isArray(page.data), table);
  assert.ok(!JSON.stringify(page.data).includes("payload_hash"), table);
}
assert.equal(
  (await op("export_data", { table: "study_streak_freezes" })).data.length,
  1,
);
assert.equal(
  (await op("export_data", { table: "study_streak_freezes" }, other)).data
    .length,
  0,
);
assert.equal(
  (await op("export_data", { table: "sessions" }, other)).data.length,
  0,
);
assert.ok((await op("report_csv")).csv.includes("Equivalências confirmadas"));
await db.exec(
  `SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${other}',false);`,
);
for (
  const table of [
    "platform_sessions",
    "platform_session_items",
    "platform_goals",
    "platform_materials",
    "platform_connected_notes",
    "platform_privacy_requests",
    "platform_entitlements",
    "platform_teachers",
    "platform_classes",
    "platform_memberships",
    "platform_assignments",
    "platform_teacher_feedback",
  ]
) {
  assert.equal(
    (await db.query(`SELECT count(*)::int AS n FROM ${table}`)).rows[0].n,
    0,
    `RLS ${table}`,
  );
}
await assert.rejects(
  () => db.query("SELECT * FROM platform_session_keys"),
  /permission denied/,
);
await assert.rejects(
  () => db.query("SELECT * FROM platform_class_invites"),
  /permission denied/,
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM platform_content_drafts"))
    .rows[0].n,
  0,
  "Learners cannot read unpublished/private answer keys",
);
await assert.rejects(
  () => db.query("UPDATE platform_entitlements SET plan='pro'"),
  /permission denied/,
);
await db.exec(
  `RESET ROLE; SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${teacher}',false);`,
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM platform_memberships"))
    .rows[0].n,
  1,
  "Teacher sees class membership metadata",
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM platform_sessions")).rows[0]
    .n,
  0,
  "Teacher has no direct access to student answers",
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM platform_teacher_feedback"))
    .rows[0].n,
  0,
  "Teacher reads feedback only through consent-aware reports",
);
await db.exec(
  `RESET ROLE; SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','${user}',false);`,
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM platform_teacher_feedback"))
    .rows[0].n,
  1,
  "Student can read their own feedback through RLS",
);
await db.exec("RESET ROLE;");
// Auth cascade must also remove private drafts and classroom records, while
// a published reviewed catalog revision stays available to other students.
await db.query("DELETE FROM auth.users WHERE id=$1", [teacher]);
assert.equal(
  (await db.query(
    "SELECT count(*)::int AS n FROM platform_content_drafts WHERE author_id=$1",
    [teacher],
  )).rows[0].n,
  0,
);
assert.equal(
  (await db.query(
    "SELECT count(*)::int AS n FROM platform_classes WHERE teacher_id=$1",
    [teacher],
  )).rows[0].n,
  0,
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM catalog_exercises")).rows[0]
    .n,
  30,
);
await db.query("DELETE FROM auth.users WHERE id=$1", [user]);
assert.equal(
  (await db.query(
    "SELECT count(*)::int AS n FROM platform_sessions WHERE user_id=$1",
    [user],
  )).rows[0].n,
  0,
);
assert.equal(
  (await db.query("SELECT count(*)::int AS n FROM platform_session_keys"))
    .rows[0].n,
  0,
);
await db.close();
console.log(
  "Platform: PostgreSQL migrations, transactions, snapshots, adaptive plans, quotas, exam secrecy, conservative grading, ownership, RLS, revocable sharing, feedback, export, deletion requests and editorial publication passed.",
);
