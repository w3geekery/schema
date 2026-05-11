# Schema Migration Status

Tracks the per-package migration off the legacy lerna `prepublish.sh`/`postpublish.sh` pipeline onto the gradle + zbb publish pipeline (plugin: `zb.schema`).

See `/migrate-packages` skill for the per-package migration loop, and the meta-repo `/migrate-content-to-zbb` skill for the repo-level bootstrap that originally added the gradle infrastructure to this repo.

## Status

| Package | Path | Pre-migration | Post-migration | Status |
|---|---|---|---|---|
| `@zerobias-org/schema-w3geekery-sme-mart` | `package/w3geekery/sme-mart` | 1.0.4 | 2.0.0 | Bootstrap (this PR) |
| `@zerobias-org/schema-w3geekery-smemart` | `package/w3geekery/smemart` | 1.0.18 | 2.0.0 | Bootstrap (this PR) |
| `@zerobias-org/schema-hl7-fhir` | `package/hl7/fhir` | 1.0.0 | 2.0.0 | Bootstrap (this PR) |
| `@zerobias-org/schema-zerobias-schemas-mcpservers` | `package/zerobias/schemas/mcpservers` | 1.0.2 | 2.0.0 | Bootstrap (this PR) |
| `@zerobias-org/schema-zerobias-schemas-agentskills` | `package/zerobias/schemas/agentskills` | 1.0.6 | 2.0.0 | Bootstrap (this PR) |
| `@zerobias-org/schema-zerobias-zerobias-base` | `package/zerobias/zerobias/base` | 2.0.6 | 3.0.0 | Bootstrap (this PR) |
| `@zerobias-org/schema-bundle` | `bundle/` | 0.0.28 | 1.0.0 | Bootstrap (this PR) |

## Notes

- All 6 packages migrated in the bootstrap PR (small enough to do in one shot).
- `zerobias.zerobias.base` got a +1 major bump (`2.x → 3.x`) because downstream `auditlogic/schema` packages will pin to `^3.0.0` in their own migration PR.
- `bundle/` uses the new universal `:updateBundle` Gradle task (root `build.gradle.kts`) instead of the legacy `scripts/buildBundleAllDeps.sh`. Workflow runs it post-publish.

## Future additions

New schema packages should:
1. Use `templates/package.json` as a starting point (with the `{vendor}`/`{code}` placeholders filled in).
2. Drop a one-line `build.gradle.kts` marker: `plugins { id("zb.schema") }`.
3. Add an `.npmrc` (copy from a sibling — the validator requires it).
4. Run `./gradlew :<path>:gate` to verify before committing.
5. Add a row to this table.
