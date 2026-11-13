# Describe a photo

This feature turns an owned private upload into an editable starting prompt. It does not reconstruct the photograph or attach a person, pose or clothing reference. Creating an image is a separate action.

## HTTP workflow

1. Read `GET /v1/capabilities`. Display the action only when `prompt_drafts.enabled` is true. Upload limits remain 20 MiB and 40 megapixels; JPEG, PNG, WebP and HEIC are supported.
2. Upload through `PUT /v1/uploads/{upload_id}` with a stable UUID, or select an existing owned upload. The original bytes remain private. Captioning does not wait for person detection.
3. Persist the account ID, a new idempotency key and the exact body `{"upload_id":"…"}` before `POST /v1/prompt-drafts`.
4. Require a nonempty task `id` and valid execution status before saving the response. Keep a recoverable `submission_id` from a busy problem response. Retry the same key/body after uncertainty; never create another task identity for a network retry.
5. Poll `GET /v1/prompt-drafts/{id}` every two seconds while foregrounded, backing off to 30 seconds on failures and honoring `Retry-After`. Reconcile when returning to the foreground. Jobs continue when the app or picker closes.
6. On `succeeded`, use `result.prompt`. Fill only an unchanged, empty composer for a freshly selected photo. Otherwise offer **Replace prompt** and **Keep my prompt**, then allow Undo. Restored tasks always require review. Keep the user's other settings intact.
7. Submit the resulting prompt through the ordinary generation API only after the user selects **Create image**.

`POST /v1/prompt-drafts/{id}/cancel` requests cancellation of that same task. Queued work cancels immediately. A running read finishes its bounded decode and discards the result; show **Stopping…** until terminal. Switching photographs stops the previous unsettled read before submitting the new one. Responses belonging to an older selection must not modify the current composer.

The resource separates `submission.state` from execution `status`. Stages include `queued`, `reading_photo` and `publishing`. These are indeterminate activities, not image-denoising percentages. Failed, empty and truncated descriptions are explicit failures. There is no token stream or image artifact for this operation.

## Authorization and retention

Native clients require Studio read/write scopes. Existing browser sessions and server application credentials use the same owner checks. Only owned upload IDs are accepted; arbitrary URLs, worker IDs, storage keys and model paths are rejected. Private thumbnails require authorization headers. Account changes must not replay another account's saved task.

PostgreSQL stores the public task and original request before dispatch; Redis owns execution, attempts and the GPU lease. Upload reservations protect pending/active work. Library maintenance reconciles completion and releases reservations after clients close. A caption result never creates a generated-image library entry. The original upload remains reusable until explicitly deleted.

## Execution profile

`zenora-photo-prompt-v1` uses the existing Qwen3.5-9B INT8 ConvRot encoder, a 512² input-pixel budget, greedy decoding, thinking off, MTP off and a 256-token output ceiling. Captions execute individually in the existing fair queue with an initial 15-second cost estimate. Generation batching, VRAM reserve, settings and checkpoint bytes are preserved.

Manifests record source/model hashes, instruction hash, preprocessing profile, output token count, native runtime versions, inference and execution timing. Fused encoder views are released in `finally` on success, cancellation and failure. MOSS Observability labels these operations **Photo description** and does not render their JSON as an image.

## Limits

Fine colors, exact counts, text, faces and garment details may be described incorrectly. Review the prompt before creating an image. A caption is not an identity or garment-transfer guarantee. Background push delivery, caption batching and exact reconstruction are outside this release.

Extremely narrow photographs can fail with a useful crop request rather than exceeding the vision input budget. The original upload remains intact.

See [HTTP examples](../../examples/workflows.http), the [OpenAPI contract](openapi.yaml) and [rollout/validation guide](../describe-photo-release.md).
