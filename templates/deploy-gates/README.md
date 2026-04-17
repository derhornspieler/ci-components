# deploy-gates — MinimalCD v4.0.0

Pre-merge validation for `continuous-delivery/app-deployments` MRs. Renders the
changed Kustomize overlays and runs six parallel gates. `perf-regression`
triggers only on prod MRs (placeholder until the Argo Workflow ships).

Kyverno is NOT installed on the cluster — the staged=prod mirror contract
(spec §4) is enforced entirely CI-side by `conftest` against the Rego policy
at `policies/staged-mirror-contract.rego`.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `app_deployments_path` | string | `.` | Repo subpath containing overlays |
| `tool_image`, `kubeconform_image`, `trivy_image`, `conftest_image`, `cosign_image` | string | Harbor-pinned | Tool images |
| `policies_dir` | string | `policies` | Rego policy dir |
| `vault_role` | string | `gitlab-ci` | JWT role for cosign public key |

## Jobs

- `gate:render` — kustomize build on changed overlays, emits `rendered/*.yaml`
- `gate:kubeconform` — K8s schema validation
- `gate:trivy-config` — manifest misconfig scan
- `gate:conftest` — OPA/Rego policies including staged-mirror-contract
- `gate:cosign-verify` — verify all image digests in rendered manifests are signed
- `gate:argocd-diff` — preview of ArgoCD sync diff (stub)
- `gate:perf-regression` — only on MRs targeting `prod` (placeholder for Argo Workflow)

## Staged mirror contract

`policies/staged-mirror-contract.rego` enforces spec §4 must-match fields
(replicas, resources, HPA min/max/target, PDB minAvailable, nodeSelector,
tolerations, topologySpreadConstraints, NetworkPolicy/CiliumNetworkPolicy rules,
container count, sidecar base images). Permitted differences: Gateway/HTTPRoute
hostnames, PVC storage (staged ≤ prod), `staged.example.com/scrubbed=true`
ConfigMaps, Kustomization namespace, certificateRefs names.

Test fixtures in `policies/testdata/staged-mirror-contract/` cover pass/fail
cases. Run locally: `conftest test --policy policies/ policies/testdata/staged-mirror-contract/<fixture>.yaml`.

## Consumer snippet

Placed in `continuous-delivery/app-deployments/.gitlab-ci.yml`:

```yaml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/deploy-gates@4.0.9
```
