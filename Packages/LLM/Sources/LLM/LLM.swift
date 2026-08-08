// LLM module — filled in during Phase 5.
//
// Will contain: LLMService wrapping MLX Swift inference over a 1–1.5B
// quantized model, with exactly three narrow prompt templates
// (categorization suggestion, grounded chat, forecast narration).
// The LLM never does arithmetic or pattern detection — that stays in the
// deterministic Budgeting/SavingsAndGoals/Forecasting code.

/// Namespace marker so the module compiles before Phase 5 adds real code.
public enum LLMModule {}
