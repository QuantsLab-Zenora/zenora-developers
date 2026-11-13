# iOS integration

Reference sources: [ZenoraClient.swift](../../examples/ios/ZenoraClient.swift). **Status: source review only; no macOS/Xcode compilation, simulator or physical-device checks have run.** The sample uses Foundation, AuthenticationServices, Security and CryptoKit. It is not an Xcode application.

Use [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession), retaining the session and supplying a presentation anchor. The example uses the iOS17.4+ [HTTPS callback API](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/https(host:path:)). Support for older iOS versions needs a separately registered/validated callback policy; do not silently accept a private scheme in production.

1. Persist a pending PKCE transaction and open its browser session. Keep `prefersEphemeralWebBrowserSession=false` to allow a valid Access browser session to be reused. The app still verifies callback state and exact URL.
2. Configure Associated Domains for the callback host, including `applinks:account.zenora.dev` and the `webcredentials` association needed by the chosen authentication-session API. Insert the real Apple team and bundle IDs into the prepared AASA template before a separately approved rollout. No association file was published here.
3. In the callback, consume the pending state once, extract the code and form POST to the fixed token endpoint. Store the replacement pair with `Vault.save`; the Keychain item uses a device-only accessibility class and one atomic item update. Keep access tokens in memory where possible and store an absolute expiry deadline. Never use UserDefaults for plaintext credentials.
4. Use `ZenoraClient.currentUser` to identify the account. Persist generation JSON bytes, UUID key, account ID and returned job ID in an account-scoped durable local record. Resend exactly those bytes/key after a lost response.
5. `image` downloads authenticated bytes through URLSession. SwiftUI `AsyncImage(url:)` alone cannot attach the needed bearer header; supply a header-aware loader and account-partitioned cache. The reference delegate refuses redirects. Do not place tokens in URLs or export a private image until the user requests it.

`SerializedRefresh` shares one in-flight task. Its exchange closure performs one form request with no automatic retry, decodes the pair and throws on OAuth errors. Only after Keychain replacement succeeds can callers resume. An unknown refresh result or persistence failure clears this device's credentials and requires sign-in. Resource503 keeps the existing session; it is not evidence for invalid_grant.

## Streams, scenes and lifecycle

Use `URLSession.bytes(for:)` or a host streaming transport with an authenticated URLRequest. Preserve SSE IDs and parse blank-line records, comments, UTF8 and multiline data. `URLSession.data(for:)` buffers a response and is unsuitable for an indefinite event stream. Drop stale attempts and duplicate IDs. The [fixture](../../examples/fixtures/progress.sse) includes real field shapes and control-event behavior.

Cancel streams when scenePhase leaves active; this does not cancel GPU work. On active, fetch saved IDs plus `/generations/active`, then resume with Last-Event-ID/current bearer. If streaming is unavailable, foreground polling starts at five seconds with backoff. Do not depend on background execution to keep the server job alive. Notifications are deferred.

Conflate preview tasks and decode at display size. Keep the last displayed frame while the next decodes. Verify camera scene length equals depth_width×depth_height×4, then decode little-endian Float32 rows; never hand a depth task's result to UIImage as if it were PNG. Camera saves create separate catalog variations. Reference boxes use oriented-image normalized coordinates, described with full journeys in [workflows](workflows.md).

Before release: Xcode compile, strict-concurrency review, Keychain lock/unlock behavior, HTTPS callback association on signed devices, app termination during submission and token rotation, account switching, private cache clearing, scene recovery, upload orientation and VoiceOver. These remain platform-validation requirements, not completed server checks.
