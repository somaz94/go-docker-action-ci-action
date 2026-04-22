.PHONY: lint test test-fixture build-fixture clean help

FIXTURE := tests/fixtures/sample_action

## Quality

lint: ## yamllint action.yml + workflows + fixtures (dockerized, no host install)
	docker run --rm -v $$(pwd):/data cytopia/yamllint -d relaxed action.yml .github/workflows/ tests/

## Testing

test: test-fixture ## Run fixture Go tests locally (no Docker / no registry)

test-fixture: ## Run `go test ./...` inside the fixture Go module
	cd $(FIXTURE) && go test ./... -v -cover -coverprofile=coverage.out

build-fixture: ## Build the fixture Docker image locally (requires Docker)
	docker build -t local/sample_action:dev $(FIXTURE)

## Cleanup

clean: ## Remove fixture coverage output and local fixture image
	rm -f $(FIXTURE)/coverage.out
	docker rmi local/sample_action:dev 2>/dev/null || true

## Help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
