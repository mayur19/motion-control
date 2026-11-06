# Motion Badminton host

The Godot desktop host owns pairing, motion ingest, swing detection, simulation,
rendering and diagnostics. The shell currently exposes the planned responsive
status layout and a deterministic 120 Hz physics configuration.

## Run

```sh
godot --path apps/host-godot
```

## Headless smoke test

```sh
godot --headless --path apps/host-godot -- --smoke-test
```

Success prints `TMB-004_HOST_SMOKE_OK` and exits with status 0. Arguments after
the second `--` are application arguments, not Godot engine arguments.

The single application version value lives at `application/config/version` in
`project.godot`; the interface reads that value at runtime.
