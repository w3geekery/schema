# `@zerobias-org/schema`

Open-source AuditgraphDB schema packages for the ZeroBias platform.

This monorepo hosts schema definitions (classes, interfaces, fields, documents, enums) that are published to npm and loaded into AuditgraphDB by the dataloader. The proprietary counterpart is [`auditlogic/schema`](https://github.com/auditlogic/schema) (`@auditlogic` scope).

- **Build pipeline:** gradle + [`zbb-publish-reusable`](https://github.com/zerobias-org/devops/blob/main/.github/workflows/zbb-publish-reusable.yml) (no lerna / no nx)
- **Per-package plugin:** [`zb.schema`](https://github.com/zerobias-org/util/blob/main/packages/build-tools/src/main/kotlin/zb.schema.gradle.kts) — extends `zb.content` with TS-twin generation against an ephemeral Neon Postgres branch
- **Third-party contributors:** start with [`CONTRIBUTING.md`](CONTRIBUTING.md). It explains the validation workflow you need to run from your fork before opening a PR.

## Local development

```bash
# Validate + write gate stamp for a single schema
./gradlew :{vendor}:{code}:gate           # depth 2 (e.g. :hl7:fhir)
./gradlew :{vendor}:{group}:{code}:gate   # depth 3 (e.g. :zerobias:zerobias:base)

# Cross-cut: ensure no two schemas share a zerobias.package block name
./gradlew validateUniquePackageNames

# zbb-driven (matches CI):
zbb gate
zbb publish
```

`testIntegrationDataloader` against a real Neon branch needs `NEON_API_KEY` and `NEON_PROJECT_ID` env vars; without them it is skipped (not failed). CI re-runs the full gate against an ephemeral branch on push.

## Adding a new schema

```bash
# Bootstraps directory + templates + .npmrc
./scripts/createNewSchema.sh package/{vendor}/{code}

# Drop the gradle marker
echo 'plugins { id("zb.schema") }' > package/{vendor}/{code}/build.gradle.kts

# Run the gate (writes gate-stamp.json — commit it)
./gradlew :{vendor}:{code}:gate
```

A new schema's `package.json` should depend on `@zerobias-org/schema-zerobias-zerobias-base@^3.0.0` and declare `zerobias.imports: ["zerobias.zerobias.platform.schema", "zerobias.zerobias.base.schema"]`. See [`CLAUDE.md`](CLAUDE.md) for the full definition reference.

## Layout

```
package/{vendor}/{code}/                # depth 2 (leaf)
package/{vendor}/{group}/{code}/        # depth 3 (leaf)
package/{vendor}/{code}/schema/         # umbrella over {vendor}.{code}
                                        # (npm name omits trailing "-schema";
                                        # validator recognises the convention)
```

## See also

- [`CLAUDE.md`](CLAUDE.md) — operational playbook + schema definition reference.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — third-party contributor guide.
- `bundle/package.json` — `@zerobias-org/schema-bundle`, lists every published schema as a dep; auto-refreshed by the publish workflow.
- `zbb.yaml` — lifecycle map between zbb commands and gradle tasks.
