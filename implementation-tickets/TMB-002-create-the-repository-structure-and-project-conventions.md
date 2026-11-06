# TMB-002 — Create the repository structure and project conventions

**Status:** Done  
**Labels:** `foundation`  
**Estimate:** 0.5 day  
**Dependencies:** TMB-001

### Implementation steps

1. Create `apps/host-godot`, `apps/controller-ios`, `apps/controller-android`, `protocol`, `tools`, and `docs` directories.
2. Add a root `README.md` describing the product, projects and local setup entry points.
3. Add `.gitignore` rules for Godot, Xcode, Swift, Android Studio, Gradle and OS-generated files.
4. Define naming, formatting and commit conventions in `docs/development.md`.
5. Add placeholders for `docs/adr`, `docs/test-plans` and `docs/playtests`.

### Acceptance criteria

- Generated build products and local credentials cannot be accidentally committed.
- A new contributor can identify every application and documentation location from the README.
- No existing PRD or architecture document is moved or overwritten.

### Evidence

- Root directory tree
- Clean `git status` after building each empty project

### Implementation log

- 2026-11-06: Created the application, protocol, tooling and documentation
  directory structure.
- 2026-11-06: Added the repository guide, project conventions and ignore rules.
- 2026-11-06: Verified representative Godot, Xcode, Gradle, Android and signing
  outputs are ignored. Clean post-build status will be rechecked as each shell
  is created.


