# Release-gate scripts

Three-stage gate that prevents broken v4.x tags from reaching consumers.
The v4.0.0 → v4.0.6 parade happened because the catalog shipped on
`yamllint` alone; this suite is the fix.

Gate #3 uses GitLab native multi-project pipelines (`trigger:project:`
+ `strategy: depend`) instead of a bash + curl + poll-loop. The
catalog CI splits into three jobs: `prep-rc-tag` (pushes the ephemeral
tag + sleeps 15s for catalog index sync), `consumer-runtime` (bridge
job that triggers the smoketest project's pipeline via
`trigger:project:` + `strategy: depend` with
`CI_COMPONENT_VERSION=rc-${CI_COMMIT_SHORT_SHA}`), and `cleanup-rc-tag`
(`when: always` — deletes the tag whether consumer-runtime passed or
failed). `push-rc-tag.sh` falls back to `CI_COMMIT_SHA` when the
source branch is deleted before the MR pipeline finishes.

## Gates

| Gate | When | What it catches |
|------|------|-----------------|
| **#1 static-render** | Every MR | input-scope errors, dangling `variables:` keys, unknown `$[[]]` interpolations, missing `spec.inputs`, malformed `!reference` |
| **#2 consumer-lint** | CHANGELOG-bump MRs | catalog-URL resolution (directory-name mismatch, chain-include drift, hidden-component visibility), catalog publish issues |
| **#3 consumer-runtime** | CHANGELOG-bump MRs | runtime bugs (yq install failures on non-alpine images, heredoc conversion bugs, env-dependent script failures) — anything that lints clean but explodes at execution |

## Flow

```
  MR opened                              MR about to release
  -----------                            -------------------
  static-render  (#1)                    static-render     (#1)
                                         consumer-lint     (#2) ── pushes rc-<sha>
                                         consumer-runtime  (#3)    triggers scratch pipeline
                                                                   rc tag deleted on exit
  MR merged -> release-tag job cuts the real semver tag only if all three gates were green.
```

## Ephemeral `rc-*` tag lifecycle

1. `push-rc-tag.sh` creates `rc-<12-char-sha>` on the catalog project.
2. Consumer gates validate against the rc tag via real catalog URLs.
3. `cleanup-rc-tag.sh` deletes the tag on exit (success OR failure).

`rc-*` tags never appear in the stable catalog; consumers only see real
semver tags cut *after* all gates are green.

## Required environment

- `CI_SERVER_URL`, `CI_PROJECT_ID`, `CI_COMMIT_SHA` — standard GitLab CI.
- `SMOKETEST_API_TOKEN` — PAT with `api` + `write_repository` on the
  catalog project (enough to create/delete rc tags and call lint API).
  Stored in Vault at `kv/services/ci/smoketest-token`.
- For gate #3 only:
  - `SMOKETEST_CONSUMER_PROJECT_ID` — ID of the dedicated smoketest
    consumer project (`continuous-delivery/ci-components-smoketest`).
  - `SMOKETEST_TRIGGER_TOKEN` — pipeline trigger token on that project.

## Smoketest consumer project (gate #3 setup)

One-time platform setup:

1. Create project `continuous-delivery/ci-components-smoketest` (public
   within the group, no deploy keys needed).
2. Add `.gitlab-ci.yml` at the project root:
   ```yaml
   include:
     - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/platform@${CI_COMPONENT_VERSION}
     - component: $CI_SERVER_FQDN/continuous-delivery/ci-components/pipeline@${CI_COMPONENT_VERSION}
       inputs:
         team: smoketest
         app: svc-monorepo
         stacks:
           - { name: core, language: python, paths: ["core/**"], project_dir: core, test_paths: [tests], coverage_threshold: 0, image_name: core, dockerfile: Dockerfile, build_context: core }
           - { name: ui,   language: typescript, paths: ["ui/**"], project_dir: ui, coverage_threshold: 0, image_name: ui, dockerfile: Dockerfile, build_context: ui }
   ```
3. Add the minimal fixture directory tree (`core/`, `ui/`, Dockerfile stubs)
   so build jobs have something to consume.
4. Settings → CI/CD → Pipeline trigger tokens → add one named
   `catalog-release-gate`. Stash the token in Vault at
   `kv/services/ci/smoketest-trigger-token`.
5. Settings → CI/CD → Job token permissions → allow inbound from
   `continuous-delivery/ci-components`.
