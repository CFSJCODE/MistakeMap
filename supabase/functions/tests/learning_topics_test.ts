import { learningTopics } from "../_shared/learning_topics.ts";

Deno.test("referências de IoT só aparecem para uma matéria relacionada", () => {
  if (
    learningTopics("Internet das Coisas").length !== 3 ||
    learningTopics("IoT I").length !== 3 ||
    learningTopics("Matemática").length !== 0 ||
    learningTopics("robotica").length !== 0
  ) {
    throw new Error("Os tópicos não foram restritos à matéria correspondente.");
  }
});
