# Protocol v1 golden vectors

This directory contains the platform-neutral executable contract for protocol
v1. Binary files are raw UDP datagrams; `manifest.json` contains their expected
decoded values, SHA-256 digests and the required rejection code for every
negative fixture.

## Layout

- `positive/*.bin`: one valid packet for every v1 message type.
- `negative/*.bin`: malformed packets that must be rejected without a crash.
- `manifest.json`: expected values and stable fixture hashes.
- `generate.rb`: deterministic source for all fixture bytes and the manifest.

No platform-specific tool is required to consume the assets: every language can
read a `.bin` file and parse JSON. Ruby is used only to regenerate or validate
the checked-in fixture set.

## Verify

```sh
ruby protocol/golden-vectors/generate.rb --check
```

## Add or change a fixture

1. Confirm the behavior is already specified in `protocol/spec.md`.
2. Add the deterministic input and expected decoded value to `generate.rb`.
3. Regenerate with `ruby protocol/golden-vectors/generate.rb`.
4. Run `--check` and all Swift, Kotlin and GDScript codec tests.
5. Review the binary diff through the manifest SHA and a hex dump.

Never silently replace an existing positive vector. A changed v1 byte sequence
is a protocol change and normally requires protocol v2. A correction must cite
the specification defect and update all codec evidence in one review.
