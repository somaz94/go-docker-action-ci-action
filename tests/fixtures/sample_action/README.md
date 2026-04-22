# sample_action fixture

Minimal fixture exercised by the go-docker-action-ci-action CI:

- `cmd/main.go` + `cmd/main_test.go` — one `greet` function with 3 table tests
- `go.mod` — no external dependencies
- `Dockerfile` — multi-stage build (golang:1.26-alpine → distroless)

Used to validate the full action flow (`setup-go` → `go test` → `registry:2` → `setup-buildx` → `docker/build-push-action` → push to `localhost:5001/actions/go-docker-action-ci-action:latest`).
