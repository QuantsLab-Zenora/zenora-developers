# Effective generation model

The platform owner selects the default for new ordinary images in Zenora Pulse. Android, iOS and server integrations continue submitting `quality` or `fast`; there is no public checkpoint-selection input.

Read `GET /v1/capabilities` on foreground return and before a new submission. `generation.model` gives the default profile, preset steps/CFG, sampler, scheduler, shift and configuration revision. The existing numeric `generation.presets` fields remain available.

An accepted generation's `model_profile` and `effective_settings` describe its captured execution. Display those saved fields for the job rather than the current capability response. A default change never changes an accepted request. Keep the original body and idempotency key when recovering a lost response or retrying a busy submission.

MOSS Quality/Fast use 10/8 steps, CFG 1, ER-SDE/Beta and shift 5. Krea2 Quality uses 12 steps/CFG 1.5 and Fast uses 8 steps/CFG 1; both use Euler/Simple and shift 1.15. Final decoding remains FP32.

Use these settings restores user-controlled settings for a new image under the current default. Exact repeat binds to the original model and validated environment. Reference operations retain the existing MOSS reference profile. Describe a photo continues using Qwen3.5-9B, independently of the text-to-image default.

Model switching can add preparation time. Show real job stages and steps, without inventing progress during model loading. The canonical OpenAPI contains the additive schemas; older requests without model metadata continue using MOSS.

Move camera currently accepts MOSS sources only. Hide its action for other `model_profile` values; the API also rejects unsupported sources. A Krea2 camera render completed during qualification but had visible edge tearing, so it did not meet the visual release criterion.
