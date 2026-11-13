# Native authentication

Use authorization code flow with PKCE S256 in an external user agent, following [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252). Refresh-token rotation and family revocation follow [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700). OAuth endpoints return OAuth JSON errors; resource endpoints return Problem Details.

## Registered clients and callbacks

| Client | Exact registered production callback |
|---|---|
| `zenora-android` | `https://account.zenora.dev/native/callback/android` |
| `zenora-ios` | `https://account.zenora.dev/native/callback/ios` |

No dynamic registration, wildcard redirect, client secret, app hash, implicit grant or password grant is supported. Release package IDs, Android signing fingerprints and Apple team IDs must be inserted into the [association templates](../../examples/associations/README.md) before a separately approved rollout. These templates are not served by this change.

Discover endpoints with `GET https://account.zenora.dev/.well-known/oauth-authorization-server`. Configure and compare the expected issuer; never trust an issuer supplied by an arbitrary callback. Metadata lists supported scopes, grant types, PKCE method and token authentication method `none`. This is OAuth, not OpenID Connect: no ID token is issued. Use `/v1/me` for the account identity.

## Sign-in sequence

1. Generate at least 32 random bytes for `state` and 32–64 for the verifier; base64url encode without padding. Verifier length must be 43–128 characters. Save state, verifier, client ID and exact redirect as one pending sign-in transaction. Expire/clear abandoned transactions and never log their values.
2. Compute `BASE64URL(SHA256(ASCII(verifier)))`. Open `/oauth/authorize?response_type=code&client_id=…&redirect_uri=…&code_challenge=…&code_challenge_method=S256&state=…&scope=studio.read%20studio.write%20community.read%20community.write` in Android Custom Tabs/Auth Tab or Apple's `ASWebAuthenticationSession`. Do not use an embedded WebView or collect a password in the app.
3. Access uses its valid browser session or its existing sign-in/registration/invitation screens. Existing invitation and email-verification rules apply. The API may grant a smaller scope set than requested; community-only users still succeed.
4. Accept only the exact expected callback. Compare `state` in constant time, consume the pending transaction once, reject a mismatch or unsolicited callback. Extract `code` only after those checks. The server binds a single-use 60-second code to client, redirect, verifier challenge and the existing Access session.
5. `POST /oauth/token`, form encoded: `grant_type=authorization_code`, `client_id`, `code`, `redirect_uri`, `code_verifier`. Send no Authorization header or client secret. Store the response safely and clear the verifier/state.
6. `GET /v1/me` with `Authorization: Bearer <access_token>`. Match the returned account to any account-scoped pending mutations before recovery.

The server reflects state after validating its allowed format. **The client verifies the returned state**; it cannot delegate this check to the server. If the browser is cancelled, close the pending transaction and retain the existing app session, if any.

## Token storage and rotation

Access tokens are opaque and expire after **10 minutes** or the remaining device-session lifetime, whichever is smaller. The device session expires **30 days after sign-in**; refreshing does not extend that absolute deadline. Store only hashes in identity. Keep refresh tokens in Keychain on iOS and AES-GCM encrypted storage with an Android Keystore key on Android. Exclude encrypted preferences and token state from device backups. Keep access tokens in memory when possible.

Refresh using form fields `grant_type=refresh_token`, `client_id`, `refresh_token`. One successful exchange consumes the refresh token and issues a new pair atomically. A second use revokes **all tokens in that device family**, including the pair from the first exchange. Different devices remain independent.

Use one serialized refresh operation per device session. Other requests await it. Persist the new refresh token atomically before sending more authenticated work. Refresh slightly before expiry, and retry an ordinary resource request at most once after a successful refresh. Do not automatically retry the refresh HTTP request. A timeout, interrupted response or crash before durable replacement leaves the outcome uncertain: clear that device's credentials and reauthorize. Replaying the old refresh token could revoke the replacement family.

An authentication-service `503` does not prove token expiry. Retain credentials and saved job IDs, back off, and retry the resource request. An explicit `401 invalid_token` allows one serialized refresh if no uncertainty exists; `invalid_grant` requires sign-in. A `403` is a permission decision, not a reason to refresh in a loop.

## Scopes and permissions

| Scope | Capability |
|---|---|
| `studio.read` | Own jobs, private library/uploads, references and camera artifacts |
| `studio.write` | Generation, cancellation, organization, uploads and camera mutations |
| `community.read` | Signed-in community browsing, own activity and contribution status |
| `community.write` | Profile/social/comment/report/preferences and sharing changes |

Private sharing previews/submissions additionally require `studio.read`; native export proofs require `community.write`. Current account entitlements are checked on every request; scopes never expand silently after account promotion. Reauthorize to obtain newly available scopes. Community suspension and publication checks remain in the community service. Native credentials cannot access existing administration, invitations, app credentials, moderator or Observability routes, even for an administrator account.

## Sessions and logout

- `GET /v1/me/sessions` lists the account's live native device sessions, including the current one.
- `DELETE /v1/me/sessions/{id}` revokes only that account's selected session; device logout uses the current ID and then clears local tokens.
- `POST /oauth/revoke`, form `client_id` and `token`, revokes the token's device family. Unknown, already revoked or other-client tokens return an empty object without disclosing validity.
- Password changes, account disabling and administrative password recovery revoke applicable native families. Re-enabling the account never restores them.
- Browser logout and mobile logout are separate. Native logout does not delete images or interrupt already accepted generation work.

Do not log tokens, cookies, code/verifier pairs, passwords or app hashes. Store account ID with pending requests and event cursors; account switching suspends recovery of the other account's queue. Do not submit it under the new token.
