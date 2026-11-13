# Zenora developer guide

Build native applications and server integrations with the versioned Zenora API.

- [API reference](https://quantslab-zenora.github.io/zenora-developers/)
- [Getting started](v1/README.md)
- [Authentication and device sessions](v1/authentication.md)
- [Generation, library, references, camera and community workflows](v1/workflows.md)
- [Describe a photo](v1/describe-photo.md)
- [Android](v1/android.md) · [iOS](v1/ios.md)
- [Errors and recovery](v1/errors-and-recovery.md)
- [OpenAPI 3.1 JSON](v1/openapi.json) · [HTTP examples](examples/workflows.http)

Production API: **https://api.zenora.dev/v1**. Authentication: **https://account.zenora.dev**.

Official mobile applications use authorization-code sign-in with PKCE through the system browser. Never embed an application hash or a service secret in a mobile app. Server integrations keep their credentials on the server.

Examples contain synthetic values. Private images require authenticated requests; access tokens do not belong in image URLs. Uploads and generations remain private unless the owner explicitly contributes an image to Discover.

Implementation and operational documentation are private. This repository contains only the public contract, integration guidance and sanitized examples. It does not contain model weights, account data or deployment credentials.

Built by **QuantsLab**.
