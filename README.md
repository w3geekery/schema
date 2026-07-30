# `@zerobias-org/schema`

Open-source AuditgraphDB schema packages for the ZeroBias platform.

This monorepo hosts schema definitions (classes, interfaces, fields, documents, enums) that are published to npm and loaded into AuditgraphDB by the dataloader. The proprietary counterpart is [`auditlogic/schema`](https://github.com/auditlogic/schema) (`@auditlogic` scope).

- **Build pipeline:** gradle + [`zbb-publish-reusable`](https://github.com/zerobias-org/devops/blob/main/.github/workflows/zbb-publish-reusable.yml) (no lerna / no nx)
- **Per-package plugin:** [`zb.schema`](https://github.com/zerobias-org/util/blob/main/packages/build-tools/src/main/kotlin/zb.schema.gradle.kts) — extends `zb.content` with TS-twin generation against an ephemeral Neon Postgres branch
- **Third-party contributors:** start with [`CONTRIBUTING.md`](CONTRIBUTING.md). It explains the validation workflow you need to run from your fork before opening a PR.

## Local development

Build and validation go through **`zbb`**, the ZeroBias build CLI
([`zerobias-org/util`](https://github.com/zerobias-org/util/tree/main/packages/zbb), `packages/zbb`):

```bash
npm i -g @zerobias-org/zbb

# First time on a machine — lifecycle commands need a loaded slot
zbb slot create local     # allocates ports, pulls env/secrets from every zbb.yaml
zbb slot load local       # preflight checks, then a subshell with slot env loaded
```

`zbb slot load` drops you into a subshell (`[zb:local]:path$`); run everything below from inside it.
Without a loaded slot, `zbb gate` exits with `Not inside a loaded slot. Run: zbb slot load <name>`.
Schema is a content repo with no long-running services, so no stack needs starting.

**Use `zbb`, not `./gradlew` directly.** `zbb` pins the JDK toolchain to Java 21; a bare `./gradlew`
uses whatever JDK is on `PATH`, and on JDK 25 Gradle 8.10.2 aborts with an opaque `25.0.2` and
nothing else. That failure means `zbb` was bypassed — not that you need a different JDK.

```bash
# Validate + write gate stamp for a single schema.
# zbb detects the subproject from cwd and prefixes the task for you.
cd package/hl7/fhir && zbb gate

# Or address it explicitly from the repo root:
zbb :{vendor}:{code}:gate           # depth 2 (e.g. :hl7:fhir)
zbb :{vendor}:{group}:{code}:gate   # depth 3 (e.g. :zerobias:zerobias:base)

# Cheap stamp check — no build, no vault
zbb gateCheck

# Cross-cut: ensure no two schemas share a zerobias.package block name
zbb validateUniquePackageNames

# Whole-repo (matches CI) — note this rewrites every gate-stamp.json
zbb gate
zbb publish
```

The gate's `testDataloader` step loads the schema into an ephemeral Neon branch via the remote
dataloader service (`DATALOADER_SERVICE_URL`, default `https://app.zerobias.com/api/dataloader`),
authenticated by **`ZB_TOKEN`**. No local Neon credentials are needed. If `ZB_TOKEN` is unset or
blank the step is **skipped (not failed)** and the stamp is still written — it records
`"testDataloader": "skipped"` rather than `"passed"`, so check that field before trusting a green
gate. CI runs the full gate on push.

## Adding a new schema

```bash
# Bootstraps directory + templates + .npmrc
./scripts/createNewSchema.sh package/{vendor}/{code}

# Drop the gradle marker
echo 'plugins { id("zb.schema") }' > package/{vendor}/{code}/build.gradle.kts

# Run the gate (writes gate-stamp.json — commit it)
cd package/{vendor}/{code} && zbb gate
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
