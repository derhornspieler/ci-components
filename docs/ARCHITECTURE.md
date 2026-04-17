# CI/CD Components Architecture

## Purpose

This repository provides standardized, reusable CI/CD pipeline components
published to the GitLab CI/CD Catalog. Teams include components in their
`.gitlab-ci.yml` instead of copy-pasting pipeline code or using fragile
cross-project file includes.

## Why CI/CD Catalog

**Before (broken):**
```yaml
# Teams had to know exact file paths inside another repo
include:
  - project: 'infra_and_platform_services/harvester-rke2-svcs'
    ref: main
    file: '/services/gitlab/ci-templates/patterns/microservice.yml'
```

**After (works):**
```yaml
# Self-contained, versioned, discoverable at /explore/catalog
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/platform@4.0.14
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/pipeline@4.0.14
    inputs:
      team: forge
      app: svc-forge
      stacks:
        - { name: core, language: python, paths: ["core/**"], project_dir: core }
```

## Component Model (v4)

Three-environment model: `dev / staged / prod`.

Shared (chain-included by all leaves):

| Component | Purpose |
|---|---|
| `platform` | Fetch platform context from Vault, language-detect anchors, rules, artifacts, package-repo hydration |
| `vault-auth` | JWT login, cosign sign/verify key fetch, SSH deploy key setup |

Leaf (per-stage):

| Component | Purpose |
|---|---|
| `pre-check` | gitleaks, commitlint, license headers, stack-validate |
| `lint` | ruff / eslint+prettier / golangci-lint per stack |
| `test` | pytest / vitest / go test, per-stack coverage threshold |
| `build` | Buildah build + push to Harbor dev, emit digest artifacts |
| `scan` | Trivy vuln+config, Syft SBOM, Cosign sign |
| `promote` | kustomize edit set image in app-deployments dev/staged branches |
| `deploy-gates` | kubeconform, trivy-config, conftest, cosign-verify, argocd-diff |

Aggregate:

| Component | Purpose |
|---|---|
| `pipeline` | Chain-includes all 7 leaves with wired stages + `needs:` |

## How It Fits Together

```
Consumer .gitlab-ci.yml
  |
  | include: platform@4.0.x + pipeline@4.0.x
  |       (pipeline chains: pre-check -> lint -> test -> build -> scan -> promote)
  v
CI/CD Catalog (this repo)
  |
  v
Pipeline runs:
  pre-check (gitleaks, commitlint, license-headers, stack-validate)
    -> lint (ruff / eslint / golangci-lint per stack)
      -> test (pytest / vitest / go test per stack)
        -> build (Buildah -> Harbor dev)
          -> scan (Trivy + Syft + Cosign)
            -> promote:dev or promote:staged (kustomize -> app-deployments)
```

## Authentication Flow

All components use GitLab JWT tokens to authenticate to Vault at runtime.
No CI/CD variables need to be configured per-project.

```
GitLab CI runner
  |
  | JWT token (id_tokens.VAULT_ID_TOKEN)
  v
Vault (JWT auth backend, role: gitlab-ci)
  |
  v
Vault KV secrets
  |
  +-- kv/platform/cluster-context         (Harbor URLs, Vault addr, package repos, ArgoCD)
  +-- kv/platform/ci-robots/harbor-dev-push  (Harbor push creds)
  +-- kv/platform/cosign/sign            (Cosign signing key)
  +-- kv/services/ci/release-gate        (smoketest tokens)
```

## Deployment Model

Components push image tags to the `continuous-delivery/app-deployments`
repo using the branch-per-environment model:

```
app-deployments repo
  |
  +-- dev branch      -> ArgoCD apps      -> dev namespaces
  +-- staged branch   -> ArgoCD apps      -> staged namespaces
  +-- prod branch     -> ArgoCD apps      -> prod namespaces (MR-gated)
```

## Versioning

- Components are published to the catalog on semver tags (e.g. `4.0.14`)
- Teams pin to specific versions: `@4.0.14`
- Breaking changes require a major version bump

## GitHub Mirror

A `sync-to-github` pipeline stage pushes a sanitized, single-commit
snapshot to `github.com/example-user/ci-components` on every push to
main. Domain names, usernames, and org-specific references are replaced
with generic placeholders. `.gitlab-ci.yml`, `.claude/`, and `memory/`
are stripped.
