# lint — MinimalCD v4.0.0

One job per language family (python/typescript/go). Loops over declared stacks
of its language. No Vault needed.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `stacks` | array | `[]` | Stack declarations (spec §7) |
| `python_image` | string | Harbor python:3.12-alpine | ruff base |
| `node_image` | string | Harbor node:20-alpine | eslint+prettier base |
| `go_image` | string | Harbor golang:1.23-alpine | golangci-lint base |

## Jobs

- `lint:python` — ruff check + ruff format --check, per python stack
- `lint:typescript` — npm ci + eslint + prettier, per typescript stack
- `lint:go` — golangci-lint run, per go stack

Empty-stack-list jobs exit 0 (no-op).

## Consumer snippet

```yaml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/lint@4.0.9
    inputs:
      stacks:
        - { name: core, language: python, paths: ["core/**"], project_dir: core }
```
