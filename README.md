# go-docker-action-ci-action

[![CI](https://github.com/somaz94/go-docker-action-ci-action/actions/workflows/ci.yml/badge.svg)](https://github.com/somaz94/go-docker-action-ci-action/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Latest Tag](https://img.shields.io/github/v/tag/somaz94/go-docker-action-ci-action)](https://github.com/somaz94/go-docker-action-ci-action/tags)
[![Top Language](https://img.shields.io/github/languages/top/somaz94/go-docker-action-ci-action)](https://github.com/somaz94/go-docker-action-ci-action)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Go%20Docker%20CI%20Action-blue?logo=github)](https://github.com/marketplace/actions/go-docker-ci-action)

A composite GitHub Action that runs Go unit tests and builds + pushes a Docker image to a local in-job registry — in a single step.

It replaces the shared CI prelude every Go-based Docker action repo tends to copy (`unit-tests` + `build-and-push-docker` jobs with `services: registry:2`, `setup-buildx`, `docker/build-push-action`).

<br/>

## Features

- One action, whole Go/Docker prelude: `setup-go` → unit tests (with optional coverage threshold) → start local `registry:2` → `setup-buildx` → `docker/build-push-action` → push to `localhost:<port>/actions/<name>:latest`
- Defaults match the standard Go Docker action layout (`go.mod`, `./...` tests with coverage, single-arch `Dockerfile` build, registry on port `5001`) — zero config for most repos
- Tunable: pinned `go_version`, subdirectory `working_directory`, `cache_dependency_path` passthrough for mono-repos, custom `test_command`, `coverage_threshold`, custom `image_name`, `dockerfile`, `build_context`, `registry_port`, and an escape hatch to disable the built-in registry (`manage_registry: false`)
- `services:` is job-scoped and unusable inside a composite — the action runs `registry:2` via `docker run -d` and stops it on `if: always()`. Callers who already declare `services: registry` can pass `manage_registry: false` to reuse it.
- Writes a per-run summary table to `$GITHUB_STEP_SUMMARY`
- Exposes `image_ref` and `test_exit_code` outputs for downstream smoke steps

<br/>

## Requirements

- **Runner OS**: `ubuntu-latest` is the tested target (Docker daemon must be available for `docker run registry:2` and `docker/build-push-action`). GitHub-hosted Ubuntu runners ship both.
- **Caller must run `actions/checkout`** before this action so that `working_directory` contains the Go module and `build_context` contains the `Dockerfile`.
- **Go toolchain** for `setup-go` — resolved from the caller's `go.mod` by default, or pinned via `go_version`.

<br/>

## Quick Start

Drop this into `.github/workflows/ci.yml` of any Go-based Docker action repo:

```yaml
name: Continuous Integration

on:
  pull_request:
  push:
    branches: [main]
    paths-ignore:
      - '.github/workflows/**'
      - '**/*.md'
  workflow_dispatch:

permissions:
  contents: read

jobs:
  ci-prelude:
    name: Unit Tests + Docker Build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: somaz94/go-docker-action-ci-action@v1
```

With all defaults it runs: `setup-go` from `go.mod` → `go test ./... -v -cover -coverprofile=coverage.out` → start `registry:2` on `localhost:5001` → `setup-buildx` → `docker/build-push-action@v7` with `push: true` and `tags: localhost:5001/actions/<repo-name>:latest`. The registry is stopped on `if: always()`.

Downstream smoke test jobs can then set `needs: ci-prelude` and consume the image reference or just `uses: ./` the action against the repository's `action.yml`.

<br/>

## Usage

### Pin the Go version

```yaml
- uses: actions/checkout@v6
- uses: somaz94/go-docker-action-ci-action@v1
  with:
    go_version: '1.26'
```

<br/>

### Enforce a minimum coverage threshold

```yaml
- uses: actions/checkout@v6
- uses: somaz94/go-docker-action-ci-action@v1
  with:
    coverage_threshold: '80'
```

The default `test_command` already emits `coverage.out`. If you override `test_command`, make sure it still writes `coverage.out` (e.g., include `-coverprofile=coverage.out`) so the threshold step can parse it.

<br/>

### Run only the Docker build (skip unit tests)

```yaml
- uses: actions/checkout@v6
- uses: somaz94/go-docker-action-ci-action@v1
  with:
    run_unit_tests: 'false'
```

Useful when unit tests live in a dedicated job and you only need the "build + push to local registry" prelude.

<br/>

### Custom test command

```yaml
- uses: actions/checkout@v6
- uses: somaz94/go-docker-action-ci-action@v1
  with:
    test_command: 'go test ./internal/... -v -cover -coverprofile=coverage.out'
```

<br/>

### Go project in a subdirectory

```yaml
- uses: actions/checkout@v6
- uses: somaz94/go-docker-action-ci-action@v1
  with:
    working_directory: action
    dockerfile: Dockerfile
    build_context: action
```

`working_directory` controls where Go tests run; `build_context` controls the Docker build context. Both typically point at the same directory.

<br/>

### Mono-repo with `go.sum` outside `working_directory`

```yaml
- uses: actions/checkout@v6
- uses: somaz94/go-docker-action-ci-action@v1
  with:
    working_directory: services/api
    cache_dependency_path: services/api/go.sum
```

<br/>

### Custom image name / port / Dockerfile path

```yaml
- uses: actions/checkout@v6
- uses: somaz94/go-docker-action-ci-action@v1
  with:
    image_name: my-action
    registry_port: '5050'
    dockerfile: docker/Dockerfile
    build_context: .
```

<br/>

### Caller manages the registry via `services:`

```yaml
jobs:
  ci-prelude:
    runs-on: ubuntu-latest
    services:
      registry:
        image: registry:2
        ports:
          - 5001:5000
    steps:
      - uses: actions/checkout@v6
      - uses: somaz94/go-docker-action-ci-action@v1
        with:
          manage_registry: 'false'
```

`manage_registry: false` makes the action skip `docker run registry:2` / cleanup. The action still builds and pushes to `localhost:<registry_port>/actions/<image_name>:latest`, so the caller's `services:` port and the action's `registry_port` must agree.

<br/>

### Consume the outputs

```yaml
- id: ci
  uses: somaz94/go-docker-action-ci-action@v1

- name: Report
  if: always()
  run: |
    echo "image_ref=${{ steps.ci.outputs.image_ref }}"
    echo "test_exit_code=${{ steps.ci.outputs.test_exit_code }}"
```

`image_ref` is always set (e.g., `localhost:5001/actions/my-action:latest`). `test_exit_code` is `0` when tests passed, and empty when `run_unit_tests: false`.

<br/>

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `go_version_file` | Path to `go.mod` (or another file) used by `actions/setup-go` as `go-version-file`. Ignored when `go_version` is set. | No | `go.mod` |
| `go_version` | Explicit Go version (e.g., `1.26`). Takes precedence over `go_version_file` when non-empty. | No | `''` |
| `cache` | Enable Go module/build cache in `actions/setup-go`. | No | `true` |
| `cache_dependency_path` | Passthrough to `actions/setup-go` `cache-dependency-path`. Leave empty to rely on setup-go's default (`go.sum` next to `go.mod`). Handy for mono-repos. | No | `''` |
| `working_directory` | Directory to run unit tests and resolve the build context from (Go module root). | No | `.` |
| `run_unit_tests` | When `true` (default), run `test_command` before the Docker build. Set `false` to skip the test phase entirely. | No | `true` |
| `test_command` | Shell command executed from `working_directory` for unit tests. Must produce `coverage.out` when `coverage_threshold` is non-empty. | No | `go test ./... -v -cover -coverprofile=coverage.out` |
| `coverage_threshold` | Minimum total coverage percent (e.g., `80`). Leave empty to skip the threshold check. | No | `''` |
| `image_name` | Image name used in the final tag `localhost:<registry_port>/actions/<image_name>:latest`. Empty derives from the current repository name. | No | `''` |
| `dockerfile` | Path to the Dockerfile, relative to `build_context`. | No | `Dockerfile` |
| `build_context` | Build context passed to `docker/build-push-action`. | No | `.` |
| `registry_port` | Host port exposed by the local `registry:2` container. Final tag is `localhost:<port>/actions/<image_name>:latest`. | No | `5001` |
| `manage_registry` | When `true` (default), run a local `registry:2` container from the action and stop it after the build. Set `false` to rely on a caller-managed `services: registry` on the same port. | No | `true` |

<br/>

## Outputs

| Output | Description |
|--------|-------------|
| `image_ref` | Full image reference that was built and pushed (e.g., `localhost:5001/actions/my-action:latest`). |
| `test_exit_code` | Exit code of the unit test command. `0` when tests passed. Empty when `run_unit_tests` is `false`. |

<br/>

## Permissions

The action itself needs no special permissions beyond what `actions/checkout` and `actions/setup-go` require. A typical caller:

```yaml
permissions:
  contents: read
```

<br/>

## How It Works

1. **Validate inputs** — `go_version` or `go_version_file` must be set; `working_directory` and `build_context` must exist; `dockerfile` must be a file inside `build_context`; `test_command` must be non-empty when `run_unit_tests: true`; `coverage_threshold` must be numeric when set; `registry_port` must be a positive integer.
2. **`actions/setup-go`** — either from `go_version_file` (default `go.mod`) or `go_version` (when explicitly set). Go module/build cache controlled by `cache`; `cache_dependency_path` is passed through verbatim.
3. **Resolve image metadata** — derives the final `image_ref` as `localhost:<registry_port>/actions/<image_name>:latest`. When `image_name` is empty, uses `${{ github.repository }}`'s name component (e.g., `my-action` for `somaz94/my-action`). Emits both `image_name` and `image_ref` as step outputs (`image_ref` is the action's output).
4. **Run unit tests** (when `run_unit_tests: true`) — `bash -c "$test_command"` from `working_directory`. When `coverage_threshold` is set, parses `coverage.out` via `go tool cover -func` and fails the action if total coverage is below the threshold. Emits `test_exit_code=0` on success.
5. **Start local registry** (when `manage_registry: true`) — reuses an existing `go-docker-ci-action-registry` container if running; otherwise `docker run -d --rm -p <port>:5000 --name go-docker-ci-action-registry registry:2`. Polls `http://localhost:<port>/v2/` for up to 15 seconds until ready.
6. **`docker/setup-buildx-action@v4`** — installs buildx with `driver-opts: network=host` so the in-job registry is reachable via `localhost`.
7. **Configure Git safe directory** — `git config --global --add safe.directory "$GITHUB_WORKSPACE"`, matching the pattern inline Go action CI workflows already use.
8. **`docker/build-push-action@v7`** — `context: build_context`, `file: build_context/dockerfile`, `push: true`, `tags: <image_ref>`. The local registry receives the push.
9. **Stop local registry** (`if: always()` when `manage_registry: true`) — `docker stop` removes the `registry:2` container (started with `--rm`). Always runs so the container doesn't leak even on test failure.
10. **Summary** — a markdown table (working directory / unit tests / coverage threshold / dockerfile / registry / image ref) is appended to `$GITHUB_STEP_SUMMARY`.

<br/>

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
