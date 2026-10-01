/// Limits supplied by the administrator's AI Studio screenshots, 2026-09-30.
/// They are per model; historical maxima in the screenshots are not live usage.
abstract final class GeminiFreePlan {
  static const models = ['Gemini 3.8 Flash', 'Gemini 3.6 Flash'];
  static const requestsPerMinute = 5;
  static const inputTokensPerMinute = 250000;
  static const requestsPerDay = 20;
}
