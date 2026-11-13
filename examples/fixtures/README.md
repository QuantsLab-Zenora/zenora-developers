# Shared sanitized fixtures

All IDs, prompts and pixels here are synthetic. No credential, browser session, private upload or model output is included.

`responses.json` maps named responses to OpenAPI schema names for Android/iOS decoding and contract checks. `progress.sse` exercises cursor/attempt handling and authorization closure. `synthetic.png` is a64×96 solid-color upload used only by examples; it is not a meaningful face/pose test.

Server HTTP evidence lives in ignored `artifacts/native-api/`; these portable fixtures are separately validated by `scripts/verify_native_docs.py`. Platform DTO compilation/device behavior remains untested until the native projects exist.
