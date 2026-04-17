# promote — MinimalCD v4.0.0

Auto-promotes to `continuous-delivery/app-deployments` branches. No prod job —
prod promotion is an MR in app-deployments from `staged` to `prod`.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `stacks` | array | `[]` | Stack declarations |
| `team` | string | required | Team slug (app-deployments dir) |
| `app` | string | required | App slug |
| `app_deployments_repo` | string | `git@gitlab.example.com:continuous-delivery/app-deployments.git` | SSH URL |
| `kustomize_image` | string | Harbor alpine:3.21 | Base image |
| `vault_role` | string | `gitlab-ci` | JWT role for SSH key |

## Jobs

- `promote:dev` — auto on `$CI_COMMIT_BRANCH == "dev"`, writes to app-deployments `dev`
- `promote:staged` — auto on `$CI_COMMIT_BRANCH == "main"`, writes to `staged`

Each runs `kustomize edit set image <stack.image_name>=<harbor_dev>/<team>/<image_name>@<digest>`
per stack, then commits + pushes.

## Consumer snippet

```yaml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/promote@4.0.9
    inputs:
      team: forge
      app: svc-forge
      stacks: [...]
```
