# scan — MinimalCD v4.0.0

Trivy vuln + config scan (fail-closed HIGH/CRITICAL), Syft SBOM, Cosign sign.
Consumes `digests/<stack>-digest.txt` from the build component.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `stacks` | array | `[]` | Stack declarations |
| `team` | string | required | Team slug |
| `trivy_image`, `syft_image`, `cosign_image` | string | Harbor-pinned | Tool images |
| `severity` | string | `HIGH,CRITICAL` | Trivy severity gate |
| `vault_role` | string | `gitlab-ci` | JWT role |

## Jobs

- `scan:image` — Trivy vuln + config, fail-closed
- `scan:sbom-and-sign` — Syft SBOM + Cosign sign (key at `platform/cosign/sign`)

## Consumer snippet

```yaml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/scan@4.0.9
    inputs:
      team: forge
      stacks: [...]
```
