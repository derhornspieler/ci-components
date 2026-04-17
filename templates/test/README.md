# test — MinimalCD v4.0.0

Per-language test jobs looping over declared stacks, with per-stack coverage
thresholds (fallback to `default_coverage_threshold`).

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `stacks` | array | `[]` | Stack declarations (spec §7) |
| `default_coverage_threshold` | number | `80` | Fallback % when stack omits `coverage_threshold` |
| `python_image`, `node_image`, `go_image` | string | Harbor-pinned | Tool images |

## Jobs

- `test:python` — pytest + coverage xml + pytest-cov, honors `install_extras` + `test_paths`
- `test:typescript` — npm ci + configurable `test_command`
- `test:go` — `go test -race -coverprofile`, threshold check via `go tool cover`

## Consumer snippet

```yaml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/test@4.0.9
    inputs:
      stacks:
        - name: core
          language: python
          paths: ["core/**"]
          project_dir: core
          coverage_threshold: 85
          install_extras: "dev,test"
```
