# Association templates — not published

These files contain placeholders, not release identities. Do not serve them until real package/bundle/team IDs and signing fingerprints are available and a deployment is approved.

- Android: publish the completed `assetlinks.template.json` as `https://account.zenora.dev/.well-known/assetlinks.json`; scope the app intent filter to `/native/callback/android` and verify it with the signed release app.
- Apple: publish the completed AASA template as `/.well-known/apple-app-site-association` with JSON content type and no redirect. Configure `applinks` and the authentication-session API's required `webcredentials` entitlement for `account.zenora.dev` in the signed app.

Exact HTTPS callbacks are fixed in identity. Neither file changes the OAuth redirect registry or grants a client secret. Local server tests use loopback/test-only callbacks; they do not validate real associations.
