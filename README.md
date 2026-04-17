# CI/CD Components

GitLab CI/CD Catalog components for the platform. Browse the catalog at
`/explore/catalog`.

## v4.x (current)

Latest: **4.0.14**. See [CHANGELOG.md](CHANGELOG.md) for per-version details.

### Load-bearing changes

- 3-environment model: `dev / staged / prod`
- Platform endpoints fetched from Vault (`platform/cluster-context`)
- Credentials from Vault (`platform/ci-robots/*`, `platform/cosign/*`)
- Explicit `stacks:` declaration + `pre-check:stack-validate`
- Staged = prod mirror, enforced CI-side via conftest + Rego
- One aggregate `pipeline` component hides the 7-leaf plumbing

### Components

Shared (chain-included):

| Component | Purpose |
|---|---|
| `_platform` | Fetch platform context from Vault, language-detect anchors, rules, artifacts, package-repo hydration |
| `_vault-auth` | JWT login, cosign sign/verify key fetch, SSH deploy key setup |

Leaf (per-stage):

| Component | Purpose |
|---|---|
| `pre-check` | gitleaks, commitlint, license headers, stack-validate |
| `lint` | ruff / eslint+prettier / golangci-lint per stack |
| `test` | pytest / vitest-or-custom / go test, per-stack coverage threshold |
| `build` | Buildah build + push to Harbor dev, emit digest artifacts |
| `scan` | Trivy vuln+config (fail-closed), Syft SBOM, Cosign sign |
| `promote` | kustomize edit set image -> push to app-deployments `dev` / `staged` |
| `deploy-gates` | Pre-merge validation in app-deployments: kubeconform, trivy-config, conftest (with staged-mirror-contract Rego), cosign-verify, argocd-diff, perf-regression (prod only) |

Aggregate:

| Component | Purpose |
|---|---|
| `pipeline` | Chain-includes all 7 leaf components with wired stages + `needs:` |

### Minimal consumer

```yaml
# forge/.gitlab-ci.yml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/platform4.0.14
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/pipeline4.0.14
    inputs:
      team: forge
      app: svc-forge
      stacks:
        - { name: core, language: python,     paths: ["core/**"], project_dir: core }
        - { name: ui,   language: typescript, paths: ["ui/**"],   project_dir: ui }
```

See `examples/` for full pilot consumer pipelines.
