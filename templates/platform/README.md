# _platform — MinimalCD v4.0.0 shared component

Exports anchors for platform endpoint fetching, language-detect skip checks,
rules, artifact schemas, and package-repo hydration. No jobs. Chain-included
by every other v4 component.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `package_repos_override` | array | `[]` | Per-language repo overrides, merged over Vault cluster-context |
| `vault_addr` | string | `http://vault.vault.svc.cluster.local:8200` | Fallback Vault addr for bootstrap |
| `vault_role` | string | `platform-ci-reader` | JWT auth role for cluster-context |
| `vault_id_token_aud` | string | `https://gitlab.example.com` | OIDC audience |
| `default_tool_image` | string | `harbor.example.com/docker.io/library/alpine:3.21` | Tooling image |

## Anchors exported

- `.fetch-platform-context` — JWT login, read `platform/cluster-context`, write `/tmp/platform-context.env`
- `.hydrate-package-repos` — write pip/npm/go/maven configs for declared stacks
- `.python-detect`, `.node-detect`, `.go-detect` — skip script for missing language markers
- `.rules-on-mr-and-main`, `.rules-on-main-only`, `.rules-on-dev-only`, `.rules-on-mr-only`
- `.artifact-scan-reports`, `.artifact-test-reports`, `.artifact-gates-reports`

## Jobs generated

None. Anchors only.

## Consumer snippet

```yaml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/platform@4.0.9
```

Jobs in other components then `!reference [.fetch-platform-context, before_script]`
to pull the endpoint map.
