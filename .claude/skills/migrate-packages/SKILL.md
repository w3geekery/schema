---
name: migrate-packages
description: Migrate the next batch of packages within an already-gradle-bootstrapped repo. Drops per-package build.gradle.kts marker, ensures .npmrc, major-bumps the version, runs zbb gate, and commits per-package.
argument-hint: "[<package-path>...] [--batch=N] [--dry-run]"
---

# Migrate Packages (per-repo companion to /migrate-content-to-zbb)

Per-repo skill — install one copy at `<repo>/.claude/skills/migrate-packages/SKILL.md` after the meta-repo skill (`/migrate-content-to-zbb`) has bootstrapped this repo's gradle pipeline.

This skill iterates package-by-package: drop the marker, fix drift the validator surfaces, major-bump, gate, commit. It assumes the repo already has a working root `build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`, `gradle-ci.properties`, and reusable-workflow `publish.yml`.

## Trigger

```
/migrate-packages [<package-path>...] [--batch=N] [--dry-run]
```

Examples:
- `/migrate-packages` — pick the next N pending packages from `MIGRATION_STATUS.md` (or `find` if no tracker).
- `/migrate-packages adobe/ccf amazon/aws` — migrate exactly these.
- `/migrate-packages --batch=5 --dry-run` — show the next 5 candidates without changing anything.

## Pre-flight

1. `git status` — must be on a feature branch.
2. Confirm the repo is gradle-bootstrapped: root `build.gradle.kts` and `settings.gradle.kts` exist, publish workflow is on the reusable. If not, abort and direct the user to `/migrate-content-to-zbb`.
3. Read the repo's CLAUDE.md (especially the major-bump rule and any kind-specific note).
4. Identify the kind (content / connector / collectorbot) by inspecting the per-package marker pattern in already-migrated packages, OR the `id("zb.*")` plugin in any sibling.
5. Identify candidates — packages WITHOUT a `build.gradle.kts` marker. Order by safest first (fewest dependencies on others, simplest yml).

## Per-package loop

For each package in the batch:

### 1. Drop the marker
Create `<package>/build.gradle.kts` with one line:
```kotlin
plugins { id("zb.schema") }
```

`zb.schema` extends `zb.content` and adds the TS-twin pipeline (generation at gate time inside the Neon branch, publish + promote in lockstep with the schema package).

### 2. Ensure `.npmrc`
If `<package>/.npmrc` doesn't exist, copy from a sibling already-migrated package (or from the repo root). Validators require it.

### 3. Run **full** `gate` (NOT just `validateContent`)
```bash
cd <package> && zbb gate
```
**Use `zbb`, never `./gradlew` directly** — `zbb` pins the JDK toolchain to Java 21. A bare `./gradlew` uses whatever JDK is on `PATH`, and on JDK 25 Gradle 8.10.2 aborts with a bare `25.0.2` and no other output. That means zbb was bypassed, not that a different JDK is needed. Run from inside the package directory and `zbb` prefixes the task with the right project path automatically.

**A loaded slot is required** for the bare `zbb gate` form. If you see `Not inside a loaded slot. Run: zbb slot load <name>`, run `zbb slot create local` (first time only) then `zbb slot load local`, and re-run the gate from inside the resulting subshell. Alternatively use the explicitly-pathed form `zbb :<project:path>:gate`, which passes straight through to gradle and needs no slot. See the repo's CLAUDE.md → "zbb setup" for detail.

**Why full `gate` matters:** the publish workflow's preflight rejects any package without a committed `gate-stamp.json`. The stamp is written by `writeGateStamp` at the end of `gate`. `validateContent` alone does NOT produce a stamp — the package will pass local file-checks but fail in CI with `gate-stamp.json is missing or invalid`.

If **`ZB_TOKEN`** is unset or blank, `testDataloader` is skipped (not failed) — and TS-twin generation is skipped along with it (it's a post-load action inside the same task). The stamp still gets written, recording `"testDataloader": "skipped"` instead of `"passed"`. Check that field before assuming the package validated; CI re-runs the full gate on push.

The validator surfaces drift. Common fixes for schemas:
- `package.json name` doesn't match the directory-derived formula → rename to match (don't change the directory). Mixed-depth supported: `package/{v}/{p}` → `@zerobias-org/schema-{v}-{p}`; `package/{v}/{g}/{p}` → `@zerobias-org/schema-{v}-{g}-{p}`.
- `zerobias.package` mismatch → fix to match the directory-derived formula (joined with dots + `.schema` suffix). If using legacy `auditmation.package`, rename to `zerobias.package`.
- `catalog.yml` missing or malformed → required at every schema package root.
- No definitions directory → at least one of `{classes, interfaces, fields, enums, documents}` must contain a `.yml`/`.yaml`/`.json` file.
- Duplicate `zerobias.package` across packages → cross-cut collision (`validateUniquePackageNames`). Two schemas can't share an AuditgraphDB block identifier.
- `package/**/ts/` showing up in git diff → that dir is gitignored and generated at gate time. Don't commit it; delete it locally and `git checkout -- .` if it sneaks in.

Re-run gate after each fix until it passes.

### 4. Major-bump version
```bash
# In <package>/package.json: bump major (1.x.x → 2.0.0, or 0.x.x → 1.0.0).
# Already-2.x is a no-op.
```
Repo convention is universal: every package gets a major bump on first gradle publish.

### 5. Commit
Conventional commit per package, e.g. for the schema repo:
```
feat(schema-<v>-<p>)!: migrate to gradle pipeline (<oldver> → 2.0.0)
```
The `!` flag is appropriate because the major bump is a breaking version transition. Stage the marker, `package.json` (version bump), **`gate-stamp.json`** (mandatory — preflight rejects without it), and any drift fixes.

**Do NOT stage `<package>/ts/`** — it's gitignored. The TS twin is regenerated on every gate run.

### 6. Verify
After committing, optionally run the publish workflow on the feature branch to confirm `detect` picks up exactly the packages you bumped:
```bash
gh workflow run publish.yml --ref <branch>
```
On a feature branch, `version` (single-writer) is skipped and `publish` runs in pre-release mode (no `latest` dist-tag). Validate the artifacts before merging to `main`.

## Picking the next batch

Order rules of thumb:
1. Skip anything in `MIGRATION_STATUS.md`'s "Flagged" section (pre-flight failures — fix the index.yml / package.json drift FIRST in a separate commit, then re-run the tracker).
2. Prefer the simplest packages first to build muscle: smallest `index.yml`, no logo, no schema dependencies.
3. Group related packages (same vendor, same standard) in one PR — the failure mode is usually shared (template drift, etc.).
4. Cap each PR around 5-10 packages — keeps review tractable and bisects clean if something breaks.

## What NOT to do

- Do NOT change `id` UUIDs — those are stable. If the validator says duplicate, find the other holder and renumber the new arrival.
- Do NOT rename directories to make names match. The validator's job is to catch metadata drift; the metadata follows the directory, not the other way round.
- Do NOT skip the major bump because "no source changed". The version transition reflects the publish-pipeline transition, not the artifact content.
- Do NOT batch unrelated packages into one commit. One commit per package keeps `git revert` precise.

## Companion docs

- Repo's `MIGRATION_STATUS.md` (if present) — source of truth for pending vs done.
- Repo's `templates/` — what a NEW package looks like in this kind. Use as reference when fixing drift.
- `org/util/packages/build-tools/.../SchemaPrimitives.kt` — validator helpers and how each error message is shaped.
- `/migrate-content-to-zbb` — the meta-repo skill that bootstrapped this repo. Use only if the repo is NOT yet gradle-bootstrapped.
