// Capture module — filled in during Phase 2.
//
// Will contain the four transaction capture paths (manual form model,
// ReceiptOCRService, LogWalletTransactionIntent, VoiceCaptureService), all
// funneling into a single TransactionWriter so validation lives in exactly
// one place.
//
// Two pieces are deliberately stubbed until real data exists (per project
// instructions): the OCR date-parsing heuristic and the merchant-category
// lookup table — both need real sample receipts / a real merchant list.

/// Namespace marker so the module compiles before Phase 2 adds real code.
public enum CaptureModule {}
