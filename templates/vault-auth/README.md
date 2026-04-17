# _vault-auth — MinimalCD v4.0.0 shared component

Vault JWT login + credential fetch anchors. Chain-included by build, scan,
promote, deploy-gates. NOT used by lint, test, pre-check (those need no Vault).

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `vault_role` | string | `gitlab-ci` | JWT role with read on `platform/ci-robots/*` |
| `vault_id_token_aud` | string | `https://gitlab.example.com` | OIDC audience |

## Anchors exported

- `.vault-auth-jwt` — re-authenticates with `vault_role` (broader than `platform-ci-reader`)
- `.cosign-sign-auth` — materializes `/tmp/cosign.key` + `$COSIGN_PASSWORD` from `platform/cosign/sign`
- `.cosign-verify-auth` — materializes `/tmp/cosign.pub` from `platform/cosign/public`
- `.ssh-deploy-key-setup` — loads SSH deploy key from `platform/ci-robots/app-deployments-deploy` into `ssh-agent`

## Jobs generated

None. Anchors only.

## Consumer snippet

Normally included transitively via the `pipeline` aggregate. Direct use:

```yaml
include:
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/platform@4.0.9
  - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/vault-auth@4.0.9

some-job:
  before_script:
    - !reference [.fetch-platform-context, before_script]
    - !reference [.vault-auth-jwt, before_script]
    - !reference [.cosign-sign-auth, before_script]
  script:
    - cosign sign --key /tmp/cosign.key ...
```
