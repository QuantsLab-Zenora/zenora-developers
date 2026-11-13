# API-only workflows

All paths below are relative to the API origin. Send bearer headers for private resources. The [contract](openapi.yaml) lists schemas and authorization per operation. [HTTP examples](../../examples/workflows.http) include complete requests.

## Generate and recover

Create a UUID key and persist it with the exact body and current account ID **before** sending `POST /v1/generations`. Defaults remain portrait 1024×1536, Quality 10 steps, CFG1, ER-SDE/Beta, shift5, previews on; Fast uses eight steps. Dimensions are multiples of16 and within capabilities. `seed:null` requests a random persisted uint32 seed. The submitted nullable seed and resolved job seed are separate values.

The `202` response is a durable submission resource. Keep `id`, `request`, `submission`, `job`, `library_item_id` and `library_stack_id`. `submission.state` is `pending`, `uncertain`, `busy`, `rejected` or `accepted`. Execution `job.status` is `queued`, `running`, `succeeded`, `failed` or `cancelled`. A missing job does not mean the request was lost.

- Response lost: retry the identical POST/key/body. Do not create another key. Changed body/context returns409. The same key belongs to only one account.
- Pending/uncertain: `GET /v1/generations/{id}` reconciles persisted state. If the ID response itself was lost, resend the original POST.
- Busy: Problem503 `scheduler_busy`, `submission_id` when persisted and `Retry-After`. Wait and retry the exact request. It remains a submission, not accepted GPU execution. A busy estimate is not a completion estimate.
- `GET /v1/generations/active` recovers accepted/pending work. Also fetch locally saved IDs because completed jobs leave the active list.
- Cancel with `POST /v1/generations/{id}/cancel`. Cancellation is cooperative; races with completion are possible. Use the returned/fetched state. Network disconnect never cancels work.
- On success fetch `…/result` PNG, `…/manifest` JSON or known `…/previews/{frame_id}` JPEG. Do not guess worker IDs. A not-ready artifact returns409.

`repeatable:true` is ordinary text-to-image batch-one mode. Only a previously repeatable job supports `replay_of`. Replay restores exact settings and binds to the validated GPU/runtime; incompatible environments or hash mismatches fail explicitly. Adaptive jobs support reuse without a byte-equality promise. Presets, per-pass seeds, queue fairness and audited FP32 final decoding are unchanged.

## SSE and mobile lifecycle

Connect to `…/events` with bearer and optional `Last-Event-ID`. Retain the SSE ID string exactly (currently Redis stream IDs); persist it beside the job and account IDs. Comments are heartbeats. JSON `data` carries attempt, execution status, stage, real completed/total steps and preview URLs. Use [JobEvent](openapi.yaml), not elapsed time, for progress.

Drop duplicate event IDs and ignore lower attempt numbers. A higher attempt resets preview/progress state and supersedes earlier execution. Never move the persisted cursor backward. `auth_required` closes the stream on expiry/revocation; `service_unavailable` or `stream_error` means reconnect with backoff after fetching state. Authorization is rechecked every15seconds with a10second deadline; revoked authorization closes within25seconds. Expiry closes at the token deadline.

Keep one preview download/decode active and only the newest pending frame. Cancel an obsolete download before decoding. Display a previous decoded frame until the new one is ready. Ignore frames from old attempts. Stop fetching previews on final status and load the final PNG. Resolve only configured-origin `/v1/…` URLs; never attach tokens to arbitrary redirects.

Backgrounding may close the stream. The job continues. Foreground recovery first fetches saved/active jobs, then reconnects from the saved cursor with a current token. If streaming is unavailable, poll every five seconds while foregrounded, backing off to10/20/30seconds on temporary failures and honoring Retry-After. App termination recovery uses the same persisted IDs/keys. Push notifications are deferred.

## Private library and organization

`GET /v1/library/items` supports `view=all|recent|favorites|unfiled|progress|trash`, `q`, `shape=portrait|landscape|square`, `page`, `album`, `kind=generated|uploads`, `grouped`, and `stack`. Pages hold24 visible entries; grouped mode returns stack representatives with member counts and preview IDs. The server clamps pages after deletions.

Ordering is newest-first with stable ID tie breaks, except ranked semantic searches and stack cover/favorite priority. Concurrent additions, moves, favorites and search ranking changes can move entries across page boundaries. Refresh from page1 and deduplicate by catalog ID when appending; page numbers are not snapshot cursors. Text search remains available when semantic service signals are missing.

`GET /v1/library/items/{catalog_id}` and `/history` return item, albums and lineage links. `source_id` addresses the corresponding generation/upload/camera resource. Artifact kinds are `thumbnail`, `display`, `original`, `manifest`; thumbnails accept `width=160…1920`, originals accept `download=true`. Use authenticated bytes with an account-partitioned image cache. Do not send private URLs to a public image proxy.

Create/rename albums with `/v1/albums`, assign/remove item IDs with `/v1/albums/{id}/items`, create/edit stacks with `/v1/stacks`, and fetch related stacks using `/v1/stacks/{id}/related`. Bulk actions support album changes, favorites, stack/unstack and Trash/restore. Preserve `undo_id` receipts; `POST /v1/library/changes/{id}/undo` may return a conflict after subsequent changes.

Trash is reversible. Permanent deletion uses `/purge` or DELETE item, returns a durable operation and checks active reference usage. Restore with `/restore`. Poll `/v1/library/operations/{id}`. ZIP export uses `POST /v1/exports` with stable key and `item_ids`, poll its ID, then authenticated `/download`. Exports expire as reported;410 requires a new export, not another generation. No image bytes live in PostgreSQL.

## Upload and reference generation

1. Persist a new upload UUID. `PUT /v1/uploads/{id}` with original file bytes, content type, percent-encoded `X-Filename` and optional JSON `X-Library-Context`. Retry the same ID and bytes. Accepted JPEG/PNG/WebP/HEIC limits:20MiB/40MP. Original bytes remain immutable; working/thumbnail derivatives apply orientation and remove display metadata.
2. `GET /v1/uploads/{id}` or `/events` waits for analysis. Show every detected figure using normalized boxes. Never select the largest person silently. Face-only figures are supported; ambiguous associations require explicit selection.
3. Persist a selection UUID. `PUT /v1/uploads/selections/{id}` with `asset_id`, role, explicit `person_id`, optional box and refinement points. Wait for its job to succeed. `/crop` and `/mask` return authenticated PNGs. Use a **new selection UUID** when changing the selection; existing IDs are immutable/idempotent. Clothing selection requires positive garment clicks.
4. Submit a generation with complete `reference_recipe.version=moss-references-v1`, operation and stable subjects. Every subject has a UUID, alias, placement and face/pose/clothes selection IDs or null. Mention `@Alias` in the unchanged prompt. Source upload IDs are separate from role selection IDs. Use at most four people.
5. Editing also supplies `source:{kind:upload|generation,id}` and `target_box` for every active subject, with distinct selected targets. The owner checks occur before immutable worker inputs are resolved. Cross-account or removed references fail; no arbitrary storage URL or model path is accepted.

References use the existing experimental50-step Euler/simple CFG3 shift5 profile, with sequential person passes and recorded seeds. Face/outfit identity remains approximate. A normal request without references follows its existing path. Failed uploads, incorrect detections and ambiguous targets retain useful context; changing references does not silently change a submitted request.

### Coordinates and orientation

Detected/returned boxes and `source_box` are `[x,y,width,height]` normalized to the **oriented working image**, origin top-left, x right/y down. Selection request `box` uses **`{x,y,width,height}`**, as do subject placements/target boxes in the output/source image respectively, bounded0…1. Points are `[x,y,label]`, normalized, `1` add and `0` remove; at most32 points. Keypoints are `[x,y]` normalized with per-joint scores; missing points require score handling. Masks are full working-image-size grayscale PNGs, white selected/black protected. Crops can be resized; retain returned source boxes rather than deriving coordinates from crop dimensions. Pixel dimensions in upload metadata refer to the oriented working image, not raw EXIF orientation.

## Camera scene and separate view

Fetch `/v1/camera/source/{generation_id}` for capabilities/existing tasks. Submit `/v1/camera/tasks` with `kind:depth`, source generation ID and stable request key. The gateway supplies its pinned pipeline version and inherited seed; callers do not supply worker IDs. Recover tasks by their public IDs.

When depth succeeds, `GET /v1/camera/tasks/{id}/manifest` gives `depth_width` and `depth_height`; `/result` contains little-endian float32 nearness, row-major, top row first. Validate exactly width×height×4bytes and finite values before preview rendering. It is a relative-nearness scene, not metric depth or a complete reconstructed object. Use the original authenticated source PNG. Final camera rendering uses the existing backend, not the approximate client preview.

For rendering submit a new camera task with `kind:camera_view`, the same `source_id`, completed depth task `scene_id` and `camera:{yaw,pitch,zoom}`. Angles are degrees, neutral(0,0,1). Positive yaw orbits toward positive world x; positive pitch raises the camera; zoom>1 narrows framing. Current render limits: yaw±30°, pitch±20°, zoom0.75…1.6. Reset locally to neutral. Cropped/hidden surfaces remain uncertain; do not imply a true photograph from every angle.

Use task events/status/cancel/result/manifest as for generation. `POST /v1/camera/tasks/{id}/save` is idempotent and creates/retains a separate library view linked to the source stack. Saving never overwrites the original. Refresh recovery uses `/camera/source/{id}` and saved task IDs. Depth output is a scene artifact and must not be displayed as a PNG.

## Community and contribution consent

Anonymous GETs browse `/v1/community/images`, detail, related, profiles, approved comments and public image assets. Signed-in scopes enable following/saves, profile updates, comments, reports and activity. Use plural `/likes`, `/saves`, `/people/{id}/follows`, `/blocks`. Download via `GET /images/{id}/assets/result/download`, not a social mutation.

Read `/v1/community/me` for the current profile/preferences and publication availability. Create/update `/profile`; a profile may remain checking until policy processing finishes. Browsing filters include selected/new/following/saved views, q, shape, handle and page. Private data is never inferred from a public publication ID. Comment POST contains its own persisted UUID and exact text for idempotent recovery; only an author can delete it. Reports go through the existing moderation queue.

To share an owned completed generation:

1. `POST /v1/community/contributions/preview` with the catalog `source_id`. Show the returned recipe and **every** asset/role. Authenticated `/private-preview/{source}/{asset}` retrieves those review images.
2. Ask for explicit rights, reference-image consent and CC-BY-4.0 license agreement. A suggested image is only a suggestion and never authorizes sharing.
3. Persist an idempotency key and POST `/contributions` with title, caption, source ID, exact `preview_hash`, all `asset_consents`, `rights_confirmed:true`, and `license:CC-BY-4.0`. Changed assets/recipe invalidate the preview with409.
4. Poll own `/contributions/{id}` for checking/held/rejected/published/withdrawn/failed status. Submission is not immediate publication. Existing safety, rights, profile and suspension checks remain authoritative.
5. DELETE withdraws the publication. Public downloads already obtained by others cannot be recalled. Changing private library organization does not constitute new consent.

Sharing suggestions and preferences are optional. Native private export authorization is minted by identity from the verified token and source ID; the app never supplies an owner ID or export proof. There is no browser-cookie impersonation.

To reuse a published recipe, `POST /v1/community/remix` with `publication_id`; retrying resumes the same owner/publication import. `GET /v1/community/remix?id=…` recovers its status using that same **publication ID**, never the optional import-row `id` in a response. Ready POST responses can omit `id`; clients must not persist it as a required value. Component compatibility and public asset hashes are verified by the existing importer. A ready response supplies a generation request with owned uploads/selections and attribution metadata; keep the original publication ID in `library_context.public_source_id` when submitting the generation. Import alone never starts generation. Removed or incompatible recipes fail clearly instead of silently dropping references.

## Photo descriptions

[Describe a photo](describe-photo.md) documents private upload selection, durable tasks, safe prompt replacement and cancellation.
