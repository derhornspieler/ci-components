# pre-check — MinimalCD v4.0.0

Pre-pipeline gate: secrets scan, commit lint, license headers, stack validation.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `stacks` | array | `[]` | Structured stack declarations (spec §7) |
| `ignore_detected` | array | `[]` | Languages to suppress in stack-validate |
| `exclude_paths` | array | `[]` | Globs to skip during marker detection |
| `gitleaks_image` | string | Harbor gitleaks | Image for gitleaks |
| `commitlint_image` | string | Harbor node:20-alpine | Image for commitlint |
| `tool_image` | string | Harbor alpine:3.21 | Image for license + stack-validate |

## Jobs

- `pre-check:secrets` — gitleaks detect, fail-closed
- `pre-check:commitlint` — conventional commits on MR
- `pre-check:license-headers` — scan *.py/.go/.ts/.js for Copyright/SPDX
- `pre-check:stack-validate` — spec §7 declaration validation

## Consumer snippet

```yaml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/pre-check@4.0.9
    inputs:
      stacks:
        - { name: core, language: python, paths: ["**"], project_dir: "." }
```
