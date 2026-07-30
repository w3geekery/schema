# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Open-source monorepo for AuditgraphDB schema packages under the `@zerobias-org` organization. Schema packages define object types (classes, interfaces, fields, documents, enums) that are loaded into AuditgraphDB by the dataloader.

Build + publish pipeline: **gradle (`zb.schema` plugin) + `zbb-publish-reusable.yml`** — no lerna, no nx. The proprietary counterpart is `auditlogic/schema` (`@auditlogic` scope).

**NOTE:** For best results, run Claude Code from meta-repo root (`~/zerobias`) to ensure access to all platform context and cross-module documentation.

## Common Development Commands

### Setup and Installation
- **Initial setup**: `npm install` (refreshes root lockfile for commitlint + tsx dev deps).

### zbb setup — do this before any gate

`zbb` is the build CLI for this repo ([`zerobias-org/util`](https://github.com/zerobias-org/util/tree/main/packages/zbb),
`packages/zbb`). Install/upgrade with `npm i -g @zerobias-org/zbb`.

**Lifecycle commands require a loaded slot.** A slot is a named local environment holding port
allocations, generated secrets, and the env vars declared across every `zbb.yaml`. Without one,
`zbb gate` refuses:

```
Not inside a loaded slot. Run: zbb slot load <name>
```

First time on a machine:
```bash
zbb slot create local     # scans zbb.yaml files, allocates ports, pulls env/secrets
zbb slot load local       # runs preflight tool checks, spawns a subshell with env loaded
```
`slot load` drops you into a subshell with the prompt `[zb:local]:path$`. Work normally inside it —
gradle, npm, and docker all see the slot env. `exit` leaves; `zbb slot load local` reconnects
instantly. Re-running `zbb slot load` with no args re-evaluates from the current directory, picking
up newly-declared vars. `zbb slot list` shows existing slots.

Schema is a content repo — it defines no long-running services, so **no stack needs to be started**.
A loaded slot is sufficient.

> **Exception:** explicitly-pathed gradle tasks (`zbb :hl7:fhir:gate`) are passed straight through to
> gradle and work **without** a slot. Bare lifecycle names (`zbb gate`, `zbb gateCheck`,
> `zbb publish`) are the ones that require it. If you get the "not inside a loaded slot" error, that
> is what you hit.

### Per-package validation

**Run gates through `zbb`, never `./gradlew` directly.** `zbb` wraps the gradle wrapper and pins the
JDK toolchain to Java 21. A bare `./gradlew` picks up whatever JDK is on `PATH`; on JDK 25 Gradle
8.10.2 aborts with an opaque `25.0.2` and nothing else. That is **not** a missing-JDK problem and
does **not** mean you should install a different JDK — it means `zbb` was bypassed.

**Preferred — `cd` into the package and run the bare task.** `zbb` walks up to the gradle root,
detects the current subproject from cwd, and prefixes the task name for you:
```bash
cd package/hl7/fhir && zbb gate          # runs :hl7:fhir:gate
```
This works at any depth and needs no hand-typed gradle path.

Explicit paths also work from the repo root. Each schema's gradle path mirrors its directory:
```bash
zbb :{vendor}:{code}:gate                  # depth 2 (e.g. :hl7:fhir)
zbb :{vendor}:{group}:{code}:gate          # depth 3 (e.g. :zerobias:zerobias:base)
```
Either way, keep the gate scoped to one package. A bare `zbb gate` from the repo root runs every
schema and rewrites every `gate-stamp.json`.

`gate` chains `validate` → `lint` → `compile` → `test*` → `buildArtifacts` → `testDataloader` →
`writeGateStamp`.

`testDataloader` loads the schema into an ephemeral Neon branch via the **remote dataloader service**
(`DATALOADER_SERVICE_URL`, default `https://app.zerobias.com/api/dataloader`), authenticated by
`ZB_TOKEN`. No local Neon credentials are involved — `NEON_API_KEY` / `NEON_PROJECT_ID` are not read
by the gate.

> **If `ZB_TOKEN` is unset or blank, `testDataloader` is skipped (not failed) and the gate still
> writes a stamp.** The stamp records this honestly as `"testDataloader": "skipped"` rather than
> `"passed"` — so check that field before trusting a green gate. Skipped is not passed.

### Repo-wide tasks
- `zbb validateUniquePackageNames` — fails if two schemas share the same `zerobias.package` block name.
- `zbb projectPaths` — used by zbb to map gradle project paths to disk locations.
- `zbb changedModules` — lists schemas modified since the last version tag.

### Lifecycle through `zbb`
The same commands the CI workflow runs (per `zbb.yaml`):
```bash
zbb gate           # → ./gradlew gate
zbb gateCheck      # → ./gradlew gateCheck
zbb version        # → ./gradlew versionStandardPackages (single-writer, main only)
zbb publish        # → ./gradlew publish
```

### Per-package helpers
Schema packages carry **no npm scripts at all** — the publish flow is fully gradle-driven. (Earlier
revisions of this file described a `correct:deps` helper backed by `scripts/correctDeps.ts`; both the
script and the package.json entries are gone.)

## Repository Architecture

### Monorepo Structure
- **`package/`**: schema packages organized by vendor/code (e.g. `hl7/fhir`, `zerobias/zerobias/base`).
- **`scripts/`**: dev helpers (`createNewSchema.sh`).
- **`templates/`**: starter files for new schemas (`catalog.yml`, `package.json`).
- **`bundle/`**: `@zerobias-org/schema-bundle` aggregate; auto-refreshed by the publish workflow's `update-bundle` step.
- **`build.gradle.kts`** + **`settings.gradle.kts`**: root validator + auto-discovery of schemas by `build.gradle.kts` marker.
- **`zbb.yaml`**: lifecycle map between zbb commands and gradle tasks.
- **`gradle.properties` / `gradle-ci.properties`**: shared + CI properties (vault refs).

### Schema Package Structure
Each schema package follows this structure:
```
package/{vendor}/{code}/
├── build.gradle.kts      # one-liner: plugins { id("zb.schema") }
├── package.json          # @zerobias-org/schema-{vendor}-{code}
├── catalog.yml           # Schema catalog entry (name, package, description)
├── .npmrc                # Registry configuration
├── gate-stamp.json       # Committed; preflight rejects packages without one
├── classes/              # AuditgraphDB class definitions (YAML)
├── interfaces/           # Interface definitions (YAML)
├── fields/               # Field definitions (YAML)
├── documents/            # Document type definitions (optional)
└── enums/                # Enum type definitions (optional)
```

### Technology Stack
- **Gradle**: build + publish orchestration via the `zb.workspace` + per-package `zb.schema` plugin family.
- **zbb**: CLI that translates lifecycle commands (gate, version, publish) to gradle tasks.
- **`zbb-publish-reusable.yml`**: shared GitHub Actions workflow that runs gate-check, version-bump (single-writer on main), matrix publish, bundle refresh, and slot sync.
- **TypeScript twin**: each schema publishes a companion `-ts` npm package generated by `@zerobias-com/platform-schema-ts-generator` against the schema loaded into an ephemeral Neon Postgres branch.
- **YAML**: schema definition format.

## Schema Definition Format

### Classes (`classes/`)
Define AuditgraphDB object types. PascalCase naming.

```yaml
# classes/GitHubRepository.yml
description: Describes a GitHub Repository Store
extends:
  - Repository
  - GitHubObject
properties:
  - fullName:
    field: repository.fullName
  - gitUrl:
    field: repository.gitUrl
viewProperties:
  "Name":
    jsonata: name
    sort: name
```

### Interfaces (`interfaces/`)
Define shared property contracts. PascalCase naming.

```yaml
# interfaces/GitHubObject.yml
description: "Common properties for GitHub resources"
properties:
  - nodeId:
    field: team.nodeId
```

### Fields (`fields/`)
Define atomic properties with types. camelCase dot-notation naming.

```yaml
# fields/repository.fullName.yml
description: 'The full name of the repository (owner/name)'
displayName: 'Full Name'
type: string
```

**Supported types:** `string`, `boolean`, `number`, `integer`, `date`, `datetime`

### Documents (`documents/`) - Optional
Define complex nested object structures.

### Enums (`enums/`) - Optional
Define enumerated value sets.

**IMPORTANT: Enum values MUST be ALL_CAPS** matching `[A-Z][A-Z0-9_]*`. The dataloader enforces this constraint. Lowercase values will fail at load time.

```yaml
# enums/team.privacy.yml
description: The level of privacy this team should have.
displayName: Privacy
values:
  - SECRET: 'Only visible to organization owners and members of this team.'
  - CLOSED: 'Visible to all members of this organization.'
```

## Validation

> **Always gate your package before pushing** — `cd` into it and run `zbb gate` (see
> [Per-package validation](#per-package-validation)). Do not invoke `./gradlew` directly.
> Local file-checks alone are not enough — schema correctness (class extends chains, field references, link bidirectionality, enum format, etc.) is only enforced by the dataloader. `gate` runs the local validator, and runs the dataloader against an ephemeral Neon branch **provided `ZB_TOKEN` is set** — without it that step is silently skipped. See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the full validation workflow — required reading for third-party contributors working from a fork.

### Validator (in repo)

`build.gradle.kts` defines a per-package `contentValidator` that checks the things the dataloader cannot or does not:

- `catalog.yml`, `package.json`, and `.npmrc` exist at the schema root.
- At least one of `{classes, interfaces, fields, enums, documents}` contains a `.yml` definition (skipped for `zerobias.deprecated: true` packages).
- **Filesystem ↔ npm ↔ zerobias-block triangulation**: `package.json` `name` and `zerobias.package` match the directory layout. For umbrella schemas (directories ending in `/schema`), the trailing segment is dropped before deriving the expected names.

The repo-wide `:validateUniquePackageNames` task fails if two schemas share the same `zerobias.package` block name.

### Gate (full validation)

`zbb gate` (from inside the package) runs the full pipeline:

1. `validateContent` — the per-package validator above.
2. `:validateUniquePackageNames` — repo-wide cross-cut.
3. `testDataloader` — loads the schema into an ephemeral Neon branch via the remote dataloader service and validates everything the dataloader checks (extends chains, link bidirectionality, enum format, viewProperties, etc.). **Skipped (not failed) when `ZB_TOKEN` is unset or blank**; CI runs it on every push.
4. `writeGateStamp` — writes `gate-stamp.json`, recording each step's status (`passed` / `skipped` / `up-to-date` / …). **`publishGuard` rejects packages without a committed, valid stamp.**

To confirm the dataloader actually ran, check the stamp: `"testDataloader": "passed"` means it ran,
`"skipped"` means it did not. Verify the stamp with `zbb gateCheck` (cheap — no build or vault
needed).

### Package Naming
- npm name: `@zerobias-org/schema-{parts joined with -}` (e.g. `@zerobias-org/schema-hl7-fhir`, `@zerobias-org/schema-zerobias-zerobias-base`).
- `zerobias.package` block: `{parts joined with .}.schema` (e.g. `hl7.fhir.schema`, `zerobias.zerobias.base.schema`).
- For umbrella schemas (`package/{vendor}/{product}/schema/`), the trailing `schema/` is dropped from the npm name; the block uses `{parent}.schema`.

## Development Workflow

### Creating a New Schema Package
1. Create directory: `mkdir -p package/{vendor}/{code}` (or `package/{vendor}/{group}/{code}`).
2. Copy templates: `scripts/createNewSchema.sh package/{vendor}/{code}` — the path is repo-root-relative and **must include the `package/` prefix**; the script exits if the directory does not already exist (step 1 creates it). Uses `templates/catalog.yml` + `templates/package.json` with `{code}` placeholders.
3. Drop the gradle marker:
   ```kotlin
   // package/{vendor}/{code}/build.gradle.kts
   plugins { id("zb.schema") }
   ```
4. Define schema content under `classes/`, `interfaces/`, `fields/`, `enums/`, `documents/`.
5. `cd package/{vendor}/{code}` and run `zbb gate`, then commit the generated `gate-stamp.json`.
   (Not `./gradlew` — see [Per-package validation](#per-package-validation).)

### Dependencies

**Required `dependencies` in `package.json`:**
- `@zerobias-org/product-{vendor}-{code}` — your product package.
- `@zerobias-org/schema-zerobias-zerobias-base` (`^3.0.0`) — base schema classes, if extending base.

**Required `zerobias.imports` in `package.json`:**
- `"zerobias.zerobias.platform.schema"` — always required (provides `Object`, `File`, etc.).
- `"zerobias.zerobias.base.schema"` — required if extending base schema classes (`Asset`, `Account`, `Repository`, etc.).

### Per-package scripts

Migrated packages have **no `scripts` block** in `package.json`. There are no `nx:prepublish` /
`nx:publish` / `validate` / `correct:deps` scripts — gradle's `zb.schema` plugin handles all of it.
If you need to validate a package, run the gate (see
[Per-package validation](#per-package-validation)), not an npm script.

### `.npmrc` Template

All packages must use the ZeroBias Package Registry. Copy this exactly:

```
@auditlogic:registry=https://pkg.zerobias.org
@zerobias-org:registry=https://pkg.zerobias.org
@zerobias-com:registry=https://pkg.zerobias.org
//pkg.zerobias.org/:always-auth=true
//pkg.zerobias.org/:_authToken=${ZB_TOKEN}
```

## Commit and Versioning
- Follow Conventional Commits: `<type>(<scope>): <subject>`
- Types: feat, fix, docs, style, refactor, perf, test, chore
- Versioning is gradle-driven: `zbb version` → `versionStandardPackages`, which bumps each changed
  package's `package.json` and commits as `chore(release): <pkg> vX.Y.Z`. Single-writer, `main` only.
- Changelogs are **not** generated. The `CHANGELOG.md` files still present in some packages are
  legacy lerna artifacts and are no longer updated by the release flow.
- No manual version bumps in pull requests

## Authentication
- Set `ZB_TOKEN` environment variable for NPM registry authentication
- Packages publish to ZeroBias Package Registry: `https://pkg.zerobias.org/`

---

## ZeroBias Task Integration

For creating schemas from ZeroBias tasks, use the skill:

```
/create-schema [task-id]
```

See **[.claude/skills/create-schema/SKILL.md](.claude/skills/create-schema/SKILL.md)** for the complete workflow.

### Quick Reference

**Orchestration Documentation:**
- [Meta-repo: DEPENDENCY_CHAIN.md](../../docs/orchestration/DEPENDENCY_CHAIN.md) - **STRICT dependency rules**
- [Meta-repo: TASK_MANAGEMENT.md](../../docs/orchestration/TASK_MANAGEMENT.md) - Task API patterns
- [Meta-repo: API_REFERENCE.md](../../docs/orchestration/API_REFERENCE.md) - Quick API reference

**Dependency Chains:**
```
Standards workflow:  vendor → [suite] → [product] → framework/standard/benchmark → crosswalk
Data workflow:       vendor → [suite] → [product] → schema → collectorbot → pipeline
```

**CRITICAL:** Schemas are on the data workflow. Vendor is required; suite and product are optional. Check/create dependencies first.

### Key APIs

```javascript
// Check dependencies exist (REQUIRED before schema)
zerobias_execute("portal.Vendor.search", { searchVendorBody: { search: "vendor" }})
zerobias_execute("portal.Product.search", { searchProductBody: { search: "vendor product" }})

// Get your party ID for assignment
zerobias_execute("platform.Party.getMyParty", {})

// Transition task to in_progress (use transitionId, NOT status)
zerobias_execute("platform.Task.update", {
  id: taskId,
  updateTask: {
    assigned: partyId,
    transitionId: "7f140bbe-4c10-54ac-922c-460c66392fad"
  }
})
```

### Workflow Transitions

| Transition | Target Status | ID |
|------------|---------------|-----|
| Start | in_progress | `7f140bbe-4c10-54ac-922c-460c66392fad` |
| Peer Review | awaiting_approval | `f017a447-0994-594d-9417-39cbc9a4de88` |
| Accept | released | `1d2e9381-f609-5e26-8bc6-7bbb65a9048d` |

**Note:** Always get actual IDs from `task.nextTransitions`.

---

## Naming Rules (CRITICAL)

The `{vendor}` and `{code}` segments must be **identical** across all identifiers. The `validate` script enforces this automatically.

```
npm package:   @zerobias-org/schema-{vendor}-{code}
catalog.yml:   {vendor}.{code}.schema
directory:     package/{vendor}/{code}/
product dep:   @zerobias-org/product-{vendor}-{code}
zb.package:    {vendor}.{code}.schema
```

**Rules:**
- `{vendor}` and `{code}` must match `^[a-z0-9]+$` — **lowercase alphanumeric only. No hyphens, no underscores, no dots.** This matches the ZB platform UI's `vspCodeValidator` constraint on product/vendor/suite codes. The API does not enforce this server-side, but the ecosystem (catalog package names, dataloader artifact resolution) requires it.
- **NEVER rename** a published schema package without coordinating with the platform team (Chris/Kevin). Renaming after classes are registered requires manual ownership transfer on the platform side. The dataloader cannot automatically reassign class ownership between packages.
- Enum values **MUST be ALL_CAPS** matching `[A-Z][A-Z0-9_]*`. The dataloader enforces this — lowercase values fail at load time.

## Important Notes
- `npm install` at the repo root only refreshes the lockfile for the commitlint dev deps. Commitlint
  is configured (`.commitlintrc.json`), but there is no `.husky/` directory and no `prepare` script,
  so **nothing enforces commit-message format locally** — follow the convention by hand.
- PRs must target the `dev` branch (not `main`)
- Versions are managed by gradle (`zbb version`), not Lerna. Packages migrated to the gradle
  pipeline take a major bump on their first gradle publish, so live versions are `2.x` / `3.x` —
  not the `1.0.0-rc.1` start of the old lerna flow.
- The gate — not an npm script — is what ensures schema integrity before publication
- Schema packages use the `zerobias` config key (dataloader supports both `zerobias` and `auditmation`)
- Extending `Element` base class enables framework linking without schema changes

## Related Documentation
- **Meta-repo CLAUDE.md:** `../../CLAUDE.md`
- **Architecture.md:** `../../Architecture.md`
- **Vendor repo:** `../vendor/CLAUDE.md`
- **Product repo:** `../product/`
- **Collector bot repo:** `../collectorbot/`
- **Existing schema examples:** `../../auditlogic/schema/package/` (e.g., `github/github/`)
