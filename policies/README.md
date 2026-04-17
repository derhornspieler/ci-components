# Policy Library

Kyverno and conftest policies consumed by the `deploy-gates` component.

## Layout

```
policies/
├── kyverno/                    # Kyverno ClusterPolicies (used by gate:kyverno-test)
│   ├── disallow-latest.yaml    # Block :latest tags and untagged images
│   └── require-resources.yaml  # Require CPU/memory requests on containers
└── conftest/                   # Rego rules (used by gate:conftest)
    ├── registry_allowlist.rego # Only allow Harbor-hosted images
    └── no_privileged.rego      # Block privileged containers and hostNetwork
```

## Adding a policy

1. Kyverno: drop a `ClusterPolicy` YAML in `kyverno/`. Run `kyverno apply` locally to test.
2. Conftest: add a `.rego` file under `conftest/` with `package main` and `deny` rules. Use `conftest test --policy conftest/ sample.yaml`.
3. Open an MR. `deploy-gates` auto-picks up both directories on next run.

## Ownership

Joint: `@platform-team @security-team`. See root `CODEOWNERS`.

## TODO

- Add registry-digest-required policy (no tag-only references in manifests)
- Add STIG-aligned policies: readOnlyRootFilesystem, runAsNonRoot, drop capabilities
- Hubble network-policy audit rules
