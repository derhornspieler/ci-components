# pipeline — MinimalCD v4.0.0 aggregate component

Chain-includes pre-check, lint, test, build, scan, promote. Most consumers
need only this plus `platform`. For `deploy-gates` (which runs in the
`app-deployments` repo, not the app repo), include that component directly.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `team` | string | required | Team slug |
| `app` | string | required | App slug |
| `stacks` | array | `[]` | Stack declarations (spec §7) |
| `default_coverage_threshold` | number | `80` | Test coverage fallback |
| `ignore_detected` | array | `[]` | Languages suppressed in stack-validate |
| `exclude_paths` | array | `[]` | Paths excluded from marker detection |
| `vault_role` | string | `gitlab-ci` | Vault JWT role |

## Stages

`pre-check -> lint -> test -> build -> scan -> promote`

`build:image` waits on pre-check + all lang-specific lint/test jobs (optional).

## Consumer snippet

```yaml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/platform@4.0.9
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/pipeline@4.0.9
    inputs:
      team: forge
      app: svc-forge
      stacks:
        - { name: core, language: python, paths: ["core/**"], project_dir: core }
```
