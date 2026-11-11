# Contributing

Thanks for your interest. This project is a measured experiment as much as a
game, so the rules below are mostly about keeping the evidence trustworthy.

## Ways to help

- **Measurements from other phones.** Sensor rate, soak results and latency on
  devices we do not have are very valuable. Use the existing tools
  (`tools/soak-report.py`, `--latency-test`, `tools/latency-frames.py`) and
  describe your setup (host, OS, network band, phone model and OS).
- **Bug reports** with the host session log excerpt (see "Privacy" below).
- **Code** for open tickets. The [roadmap](docs/roadmap.md) and
  [ticket index](implementation-tickets/README.md) show what is ready; gameplay
  tickets are blocked until the swing-laboratory gate passes.
- **Docs** fixes and clarifications.

Please open an issue before starting a large change, so we can agree on scope
and on which ticket it belongs to.

## Workflow

1. Read the relevant ticket in `implementation-tickets/`, including its
   acceptance criteria and implementation log.
2. **Write the failing test first**, then the fix.
3. Keep changes small and focused. Follow the existing structure of each app.
4. Run the tests for every codebase you touched (below).
5. Update docs, the ticket's implementation log and, for design changes, an ADR.
6. Commit with a conventional message and open a pull request against `main`.

### Commit messages

```text
<type>: <description>

<optional body>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.

### Pull requests

- Explain what changed and why, and link the ticket.
- Include a test plan: which suites you ran, and on which devices if physical.
- State clearly which results are physical, synthetic or estimated.

## Tests

```sh
# Host (Godot): each test prints TMB-…_OK and exits 0. Use a timeout.
for t in apps/host-godot/tests/*_test.gd; do
  name=$(basename "$t" .gd)
  timeout 120 godot --headless --path apps/host-godot --script "res://tests/$name.gd" \
    -- --output="${TMPDIR:-/tmp}/$name.jsonl"
done

python3 -m pytest -q tools/                                     # tools
(cd apps/controller-android && ./gradlew testDebugUnitTest)     # Android
(cd apps/controller-ios && xcodegen generate && xcodebuild -project MotionControllerIOS.xcodeproj \
  -scheme MotionControllerIOS -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' test)   # iOS
```

## Code conventions

- **GDScript:** use explicit types (`var x: float = …`); the project treats
  inferred-Variant warnings as errors. Store 64-bit IDs as decimal strings in
  JSON.
- **Protocol:** big-endian, strict validation, reject rather than repair. Any
  protocol change updates `protocol/spec.md`, the golden vectors and all three
  codecs (Swift, Kotlin, GDScript) in the same change, and needs an ADR.
- **Coordinates:** detection and gameplay code use only the common racket
  frame. Never branch on platform or handedness there.
- **Timing:** gameplay must not depend on packet arrival rate or display rate.
  Use sensor timestamps; never wall-clock time for motion age.
- **Immutability of data:** raw captures are never edited; label corrections
  are appended as new revisions.

## Evidence honesty

- Never present synthetic, automated or estimated results as physical
  measurements. Label each result's category.
- Never tune detector thresholds on held-out sessions. Held-out data is
  evaluated once with a frozen configuration.
- Record gaps, deviations and owner decisions explicitly in the ticket log.

## Data and licensing

- Contributions are accepted under the [MIT license](LICENSE).
- **Do not commit third-party datasets** or anything derived from them
  (converted files, per-sample values, plots). In particular, BadminSense
  `BADS_CLL` is CC BY-NC-ND and incompatible with this repository;
  `tools/test_no_external_data.py` fails the build if such files are tracked.
  Keep external data in git-ignored `external-data/` or outside the repo.
- Your own motion captures may contain personal movement data; share them only
  if you choose to, and not in this repository by default.

## Privacy and secrets

- Do not commit signing team IDs, provisioning profiles, keystores, `.env`
  files or credentials. The iOS project reads `DEVELOPMENT_TEAM` from your
  environment.
- Redact device identifiers (UDIDs, ECIDs, serial numbers, adb serials) from
  `xcrun devicectl`, `xcodebuild` and `adb` output before posting it.
- Host screenshots and `--print-session` output show the live pairing secret.
  Do not post them while that session is active.
- Running a secret scanner (for example `gitleaks detect`) before pushing is
  recommended.

## Safety

When testing with real phones: use a wrist strap, clear the space, and never
swing at full force. Calibration and detection are designed around controlled
swings.
