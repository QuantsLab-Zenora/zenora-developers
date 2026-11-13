# Zenora API v1

Start with [authentication](authentication.md), then follow the [workflows](workflows.md). The API supports native Android/iOS applications and server integrations.

1. Sign in through Access using PKCE, or use server-side application credentials.
2. Fetch the current user and capabilities. Studio access is checked separately from community access.
3. Persist the exact generation request and a unique idempotency key before submitting.
4. Read the saved submission and job state; consume SSE progress using its event cursor.
5. Download previews and completed artifacts with authentication headers.

The API reference is generated from the released OpenAPI 3.1 contract. Versioned paths begin with `/v1`; IDs are opaque. Preserve the request key when retrying after an uncertain response. See [errors and recovery](errors-and-recovery.md).

The public reference is read-only. Run authenticated requests from a native application, server or the supplied HTTP examples; browser cross-origin access is not an authentication workaround.

Existing published clients remain supported during the repository migration. Documentation publication does not change account permissions, generation settings or API availability.
