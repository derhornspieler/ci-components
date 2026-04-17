# build — MinimalCD v4.0.0

Loops over declared stacks, builds one image per stack with Buildah, pushes to
Harbor dev (from `platform/cluster-context.harbor_dev_registry`), emits digest
artifacts at `digests/<stack.name>-digest.txt`.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `stacks` | array | `[]` | Stack declarations (spec §7) |
| `team` | string | required | Image repo prefix `<team>/<image_name>` |
| `buildah_image` | string | Harbor buildah/stable | Buildah runner image |
| `vault_role` | string | `gitlab-ci` | JWT role for harbor-dev-push creds |

## Jobs

- `build:image` — single job, iterates stacks internally. Produces per-stack digest artifacts.

## Consumer snippet

```yaml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/build@4.0.9
    inputs:
      team: forge
      stacks:
        - name: core
          language: python
          image_name: forge-core
          dockerfile: Dockerfile
          build_context: core
          paths: ["core/**"]
          project_dir: core
```
