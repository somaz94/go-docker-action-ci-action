# CLAUDE.md

<br/>

## Project Structure

- Composite GitHub Action (no Docker image — `runs.using: composite`)
- Replaces the shared CI prelude every Go-based Docker action repo copy-pastes: `unit-tests` job (`setup-go` + `go test ./... -cover`) + `build-and-push-docker` job (`services: registry:2`, `setup-buildx`, `docker/build-push-action@v7` pushing to `localhost:5001/actions/<repo>:latest`)
- Defaults match the standard somaz94 Go Docker action layout (`go.mod`, single-arch build, registry on port `5001`) — zero config for `env-output-setter` / `contributors-action` / `go-changelog-action` / `go-git-commit-action` / `major-tag-action` / `template-go-action`
- `services:` can't be declared inside a composite action (it's job-scoped), so the action runs `registry:2` via `docker run -d --rm` and stops it on `if: always()`. Callers who already have their own `services: registry` can pass `manage_registry: false` to reuse it.
- Smoke test portions (`docker run <image>`, action-level behavior checks) deliberately stay in each caller's own jobs — this action covers only the common prelude, not action-specific assertions.

<br/>

## Key Files

- `action.yml` — composite action (**15 inputs**, **3 outputs**). Two `setup-go` steps gated on `go_version` empty/non-empty (both passthrough `cache_dependency_path`), followed by resolve image metadata → optional unit tests + coverage threshold → optional registry startup → `setup-buildx` → safe-directory config → `docker/build-push-action@v7` (with `build-args` passthrough, exposes `digest` as `image_digest` output) → `if: always()` registry cleanup → summary. All `run:` steps that matter use `working-directory: ${{ inputs.working_directory }}`.
- `tests/fixtures/sample_action/` — minimal Go module (`go.mod` no external deps, `cmd/main.go` + `cmd/main_test.go` with 3 table tests, `Dockerfile` multi-stage build to distroless, `ARG FIXTURE_BUILD_ARG` + `LABEL fixture.build_arg=...` so CI can assert `build_args` passthrough landed as a label). Plus a `Dockerfile.fail` fixture (`RUN false`) that the failure-path CI job uses to assert the action fails + cleans up the registry when `docker build` fails.
- `cliff.toml` — git-cliff config for release notes.
- `Makefile` — `lint` (dockerized yamllint), `test` / `test-fixture` (runs fixture `go test ./...` locally, no Docker / registry needed), `build-fixture` (docker build locally), `clean`.

<br/>

## Build & Test

There is no local "build" — composite actions execute on the GitHub Actions runner.

```bash
make lint            # yamllint action.yml + workflows + fixtures (dockerized)
make test-fixture    # go test ./... inside tests/fixtures/sample_action (no Docker needed)
make build-fixture   # docker build -t local/sample_action:dev against the fixture (needs Docker)
make clean           # remove coverage.out + local fixture image
```

`make lint` only needs Docker. `make test-fixture` only needs Go. `make build-fixture` needs Docker. A fully end-to-end local check (registry + push + pull) is intentionally not wired — use the `ci.yml` workflow for that.

<br/>

## Workflows

- `ci.yml` — `lint` (yamllint + actionlint) + `test-action` (defaults, dynamically derives expected `image_ref` from `$GITHUB_REPOSITORY`, asserts `image_digest` starts with `sha256:`) + `test-action-notest` (custom `image_name=sample-action`, `image_tag=sha-${{ github.sha }}`, `registry_port=5050`, `run_unit_tests=false` — asserts empty `test_exit_code` and tagged image_ref; does **not** try to pull because action-managed registry is torn down at the end of the action step) + `test-action-external-registry` (caller declares `services: registry:2`, action runs with `manage_registry=false` + `coverage_threshold=50` + `build_args: FIXTURE_BUILD_ARG=ci-smoke`, then pulls image pinned by digest and inspects the resulting image for `LABEL fixture.build_arg=ci-smoke` to prove the build_args passthrough landed) + `test-action-failure` (uses `Dockerfile.fail` with `RUN false` under `continue-on-error: true`, asserts outcome=failure, then confirms the `go-docker-ci-action-registry` container was cleaned up even on failure) + `ci-result` aggregator.
- `release.yml` — git-cliff release notes + `softprops/action-gh-release@v3` + `somaz94/major-tag-action@v1` for the `v1` sliding tag.
- `use-action.yml` — post-release smoke test. Runs `somaz94/go-docker-action-ci-action@v1` against the fixture in two flavours: defaults (action-managed registry) and `manage_registry=false` with caller-declared `services: registry` + `coverage_threshold=80`.
- `gitlab-mirror.yml`, `changelog-generator.yml`, `contributors.yml`, `dependabot-auto-merge.yml`, `issue-greeting.yml`, `stale-issues.yml` — standard repo automation shared with sibling `somaz94/*-action` repos.

<br/>

## Release

Push a `vX.Y.Z` tag → `release.yml` runs → GitHub Release published → `v1` major tag updated → `use-action.yml` smoke-tests the published version against the fixture (both action-managed and caller-managed registry paths).

<br/>

## Action Inputs

Required: none (fully default-driven for somaz94 Go Docker action layout).

Tuning: `go_version` / `go_version_file`, `cache` (default `true`), `cache_dependency_path` (default `''`), `working_directory` (default `.`), `run_unit_tests` (default `true`), `test_command` (default `go test ./... -v -cover -coverprofile=coverage.out`), `coverage_threshold` (default `''`), `image_name` (default `''`, derives from repo name), `image_tag` (default `latest`), `dockerfile` (default `Dockerfile`), `build_context` (default `.`), `build_args` (default `''`, multiline passthrough), `registry_port` (default `5001`), `manage_registry` (default `true`).

See [README.md](README.md) for the full table.

<br/>

## Internal Flow

1. **Validate inputs** — `go_version` or `go_version_file` must be set; `working_directory` / `build_context` must exist; `dockerfile` must be a file inside `build_context`; `test_command` non-empty when `run_unit_tests: true`; `coverage_threshold` must be numeric when set; `registry_port` must be a positive integer; `image_tag` must match the Docker tag regex `^[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}$`.
2. **`actions/setup-go`** — gated on `go_version` being non-empty. When `working_directory != '.'`, `go-version-file` is rewritten to `${working_directory}/${go_version_file}` so `actions/setup-go` finds the right file from the repo root. `cache_dependency_path` is forwarded verbatim (both gated branches) so mono-repos can point setup-go at the correct `go.sum` without going through `working_directory` rewriting.
3. **Resolve image metadata** — derives `image_ref = localhost:<registry_port>/actions/<image_name>:<image_tag>`. When `image_name` is empty, uses `${GITHUB_REPOSITORY##*/}` (e.g., `my-action` for `somaz94/my-action`). Emits `image_name` and `image_ref` as step outputs; top-level `outputs.image_ref` is wired to this single step id.
4. **Run unit tests + coverage threshold** (`inputs.run_unit_tests == 'true'`, single step) — `bash -c "$test_command"` from `working_directory`. Emits `test_exit_code=0`. If `coverage_threshold` is non-empty, reads `coverage.out` via `go tool cover -func`, parses `total:` row with awk, compares against the threshold with `awk -v cov=... -v thr=... 'BEGIN {exit (cov + 0 >= thr + 0) ? 0 : 1}'` (avoids `bc` dependency and shell interpolation injection), and fails the action with `::error::` if below threshold. Single step keeps the composite-output single-step-id rule intact for `test_exit_code`.
5. **Start local registry** (`inputs.manage_registry == 'true'`) — reuses an existing `go-docker-ci-action-registry` container if running; otherwise `docker run -d --rm -p <port>:5000 --name go-docker-ci-action-registry registry:2`. Polls `http://localhost:<port>/v2/` for up to 15s until HTTP 200. Fixed name (not per-run) so re-invocations within the same job reuse.
6. **`docker/setup-buildx-action@v4`** — `install: true`, `driver-opts: network=host` (so buildx can reach `localhost:<port>`).
7. **Configure Git safe directory** — matches the pattern every inline Go action CI workflow uses. Needed because `docker/build-push-action` reads git metadata under `$GITHUB_WORKSPACE`.
8. **`docker/build-push-action@v7`** — `context: build_context`, `file: build_context/dockerfile`, `push: true`, `tags: <image_ref>`, `build-args: <build_args>` (multi-line passthrough). The local registry receives the push. The `digest` output emitted by `docker/build-push-action` is re-exported as the action's top-level `image_digest` output.
9. **Stop local registry** (`if: always() && inputs.manage_registry == 'true' && steps.registry.outputs.name != ''`) — `docker stop` removes the container (started with `--rm`). Always runs so a failed build or test failure doesn't leak the container. **Side effect:** downstream steps in the same caller job cannot reach the registry after this — when `manage_registry: true`, pulling pushed images from the same job is impossible. Callers who need to pull must either (a) use `manage_registry: false` with their own `services: registry`, or (b) rely on `image_ref` / `image_digest` outputs for downstream pinning without actually pulling.
10. **Summary** — a markdown table (working directory / unit tests / coverage threshold / dockerfile / manage_registry + port / image ref / image digest when non-empty) is appended to `$GITHUB_STEP_SUMMARY` (runs on `if: always()` so a failed run still gets a summary showing what was attempted).

<br/>

## Composite Output Wiring

Three outputs (`image_ref`, `image_digest`, `test_exit_code`), all following the single-step-id rule that Phase B (`go-kubebuilder-test-action`) established — a composite top-level `outputs.<name>.value: ${{ steps.<id>.outputs.<name> }}` only tracks one `steps.<id>`:

- `image_ref` is set by the `meta` step, which always runs. Safe.
- `image_digest` is the native `digest` output of the `build` step (`docker/build-push-action@v7`), which always runs on the success path. On failure paths the build step itself fails so the output may be empty — downstream code should not assume it's set when `image_ref` is set (unlike `image_ref` which always exists).
- `test_exit_code` is set inside the `unit_tests` step, which is gated on `run_unit_tests == 'true'`. When gated off, the step doesn't run and the output is empty — documented as "empty when `run_unit_tests: false`" in the README. This is intentional; if the caller cares they can branch on `if [ -n "${{ steps.ci.outputs.test_exit_code }}" ]`.

The coverage-threshold logic deliberately lives inside the same `unit_tests` step rather than a separate `if:`-gated step. That keeps `test_exit_code` tied to a single step id even when threshold failures happen: a coverage-below-threshold `exit 1` inside the step makes the step fail, the composite fails, and the output is empty (same contract as "tests weren't run at all"). If you ever need a separate output for coverage percent, set it from inside the same step via `echo "coverage=..." >> "$GITHUB_OUTPUT"` rather than splitting into a new step.

The failure-path steps (registry cleanup, summary) do not feed action outputs — they only run `if: always()` for side-effects — so the single-step-id rule is still unbroken.
