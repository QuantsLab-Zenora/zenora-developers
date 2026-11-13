# Android integration

Reference sources: [ZenoraClient.kt](../../examples/android/ZenoraClient.kt). **Status: source review only; no Gradle compilation, emulator or physical-device validation has run.** This is networking/authentication reference code, not a finished Android app.

The sample uses Android framework JSON/network/cryptography APIs plus AndroidX Browser Custom Tabs in the host app. Invoke blocking calls on a background dispatcher. Choose and lock host-app dependencies when the Android project exists; this repository does not invent a second Gradle application. [Android Auth Tab](https://developer.android.com/reference/androidx/browser/auth/AuthTabIntent) can replace the browser launcher after host integration and callback testing. Keep the external browser and PKCE semantics in either case.

1. Persist one pending sign-in transaction before `PendingSignIn.open`. Register an exact HTTPS App Link intent filter for host `account.zenora.dev`, path `/native/callback/android`, BROWSABLE/DEFAULT and `autoVerify=true`. Insert release package and certificate SHA256 into the prepared association template during a future rollout.
2. Route the verified callback to that pending transaction, call `code(callback)`, then consume/clear it. Reject duplicated state/code query parameters. Form POST to the metadata's fixed token endpoint with the saved verifier. No client secret is needed.
3. Save tokens with `TokenVault`; exclude `zenora_native_credentials` from Auto Backup/data-extraction rules. [Android Keystore AES-GCM](https://developer.android.com/reference/kotlin/android/security/keystore/KeyGenParameterSpec) protects the key. A key invalidation/decryption error requires clearing credentials and signing in. Persist the absolute token deadline separately; response `expires_in` is relative to the response time.
4. `currentUser` verifies the account before resuming account-scoped pending mutations. Use `generate(savedBody,savedKey)` after saving those exact bytes/key to Room or another existing durable app store. Do not regenerate keys in a ViewModel retry callback.
5. For private images use `image(token,path)` or a host image-loader request with the bearer header. The example refuses cross-origin paths/redirects. Partition memory/disk caches by account and disable token logging. Download originals to a temporary private file before explicit MediaStore export.

Token endpoint form fields and errors are in [authentication](authentication.md). `SerializedRefresh` prevents two local refresh requests: pass the refresh token seen by the original401; if another request already rotated it, reuse the stored replacement. The exchange callback must have automatic retries disabled. If the response is uncertain, clear the device token state and sign in. Never attach Authorization or app-hash headers to token requests.

## Progress and recovery

Use a streaming HTTP client with bearer and Last-Event-ID; do not use a browser EventSource. Parse UTF8 across chunk boundaries, blank-line-delimited records, multiline `data`, `id`, `event`, and heartbeat comments. See the [SSE fixture](../../examples/fixtures/progress.sse). Record attempt and cursor with each job. Drop stale attempts/duplicates and cap individual records at256KiB.

Tie streaming to the foreground lifecycle (`repeatOnLifecycle(STARTED)` or host equivalent). Losing the collection cancels only the HTTP stream, not generation. On STARTED, fetch `/generations/active` and locally saved IDs, then reconnect. WorkManager/push are not necessary for server generation to continue. Poll every five seconds in foreground if streaming fails, with backoff.

Keep a conflated channel for preview URLs: one active fetch/decode and one newest pending frame. Cancel old-attempt downloads. Decode to display size, not full PNG size for every preview. On success load the original/downloadable PNG separately.

The API-only recipes, oriented normalized masks, camera float32 decoding, sharing consent and public/private distinction are documented in [workflows](workflows.md). Use generated typed DTOs from OpenAPI or distinct Kotlin wrappers for GenerationId, LibraryItemId, UploadId, SelectionId and CameraTaskId; a String's UUID-like shape is not a conversion rule.

Before release: compile the host app, verify signed App Links on a physical device, test process death, rotating refresh interruption, account switching, private-image cache isolation, slow network uploads, background/foreground recovery and accessibility. None of those checks are claimed by the Windows server tests.
