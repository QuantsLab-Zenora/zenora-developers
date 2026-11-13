# Errors and recovery

Versioned resources use `application/problem+json` with `type`, `title`, HTTP `status`, `detail`, stable `code`, `request_id`, `retryable`; optional `submission_id` and `retry_after` preserve recovery context. `X-Request-ID` matches the body. Callers may supply a1–128character request ID using letters, digits, `._:-`; otherwise one is generated. Do not include a prompt or secret in it.

| HTTP/code | Action |
|---|---|
|400 `invalid_request`|Correct headers/shape. Never mix cookie, app-hash and native bearer authentication.|
|401 `invalid_token`|One serialized refresh if its outcome is certain; otherwise sign in. Keep pending jobs.|
|403 `insufficient_scope`|Inspect entitlements/scopes. Explain denied Studio access. No automatic retry or privilege escalation.|
|404 `not_found`|Unknown, inaccessible or another account's resource; do not distinguish ownership publicly.|
|405 `method_not_allowed`|Use the documented operation.|
|409 `conflict`|Key/body mismatch, not-ready result, changed preview/undo state or immutable selection conflict. Correct context, preserving the original pending request.|
|410 `gone`|Removed item or expired export. Replace missing references or create a new export.|
|413 `payload_too_large`|Reduce file/request size before a new mutation.|
|422 `validation_error` / `generation_rejected`|Correct invalid dimensions, references, masks or settings. A rejected persisted submission can include its ID.|
|429 `rate_limited`|Honor Retry-After; bounded jittered retry.|
|503 `scheduler_busy`|Retry-After5seconds; reuse the saved generation body/key and `submission_id`. No duplicate request.|
|503 `temporarily_unavailable`|Retain tokens and durable context; back off. Authentication outage is not logout.|

An execution failure is usually a successful job-status response containing `job.status=failed` and an error with a backend code/message. OOM, numerical failure, token overflow, unsupported replay environment and deterministic adapter errors are not transport retries. Preserve settings and show a useful correction. Cancellation is a terminal state, not an error requiring replacement generation.

OAuth `/oauth/*` errors use `application/json` `{error,error_description}`. `invalid_request`, `invalid_client`, `invalid_scope`, `access_denied`, `unsupported_grant_type` and `invalid_grant` are terminal for that auth transaction. Retry temporary503/429 only where no token rotation may already have committed. A refresh timeout/unknown outcome requires reauthorization. Never repeatedly replay an old refresh token.

## Retry ownership

Persist exact asynchronous mutation bodies/keys before network access. Use one retry owner in the client; disable automatic transport retry for POST/token. Resource GETs can retry with bounded exponential backoff and jitter. Respect `Retry-After` seconds. Display submission state separately from actual GPU state. Disconnecting an SSE client never sends cancellation.

Recommended client deadlines: JSON15seconds, submit30seconds, original upload120seconds, image download60seconds with cancellation, SSE no overall deadline with a heartbeat/read watchdog. A submit timeout means **uncertain**, not failed. Server dependency deadlines are bounded: identity10seconds, library15seconds (longer artifact stream lifetime), community120seconds, worker JSON8seconds. Local resource failures return503 rather than claiming success.

For uncertainty without a known public ID, resend the original key/body. With an ID fetch it before reconnecting. On app return recover saved IDs and active work before consuming new events. Do not clear a successful image because an outdated SSE attempt arrives later.

Uploads use a persistent UUID and same original bytes. A partial/network failure can be retried; do not generate another upload ID merely because acknowledgement was lost. A selection uses a distinct UUID for each immutable choice. Deletion may fail409 while active work uses the asset. Preserve the selected reference in the UI until server confirmation.

Private artifacts require headers on every request, including cached-image loaders and resumed downloads. Partition disk caches by account and clear private cached data on logout. Do not use token query parameters, public image optimizers or unrestricted redirect following. A revoked token must not retrieve a previously uncached artifact.

SSE events `auth_required`, `service_unavailable` and `stream_error` carry a `code`, then close. Refresh/reauthorize as appropriate, fetch state, reconnect with Last-Event-ID. The server bounds event records to256KiB. Clients should retain one newest pending preview and cap decoded-image memory. Unsupported streaming falls back to foreground polling every five seconds with failure backoff.

## Troubleshooting

- Feature404 locally: enable the feature only in the isolated identity, Access and gateway processes. No public activation is part of this milestone.
- Callback stays in browser: validate exact registered URL, package/team identity, signing fingerprint and association files; do not replace it with a wildcard.
- Community works but generation403: account lacks Studio access, or the token was issued without Studio scopes.
- Reference422: wait for analysis/selection, check person ID and normalized oriented-image coordinates, and ensure the selection role matches the subject role.
- Camera result is binary: depth tasks return float32 nearness, while camera_view results return PNG.
- Publication409: fetch a fresh sharing preview and ask consent again if its assets changed.
- Jobs disappear from active list: fetch saved IDs or the private library; terminal jobs are not active work.
- Report issues using request ID, endpoint, status/code and timestamp. Do not attach access tokens, passwords, private image bytes or unrequested prompts.
