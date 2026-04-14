# Contributing to `zerobias-org/schema`

This guide is for **third-party contributors** working from a fork of this repository (e.g. `your-org/schema`). It explains how to validate a schema package end-to-end before opening a pull request, and what to expect from CI once the PR is open.

If you are a ZeroBias employee with access to internal tooling, you may have additional shortcuts available — but everything in this document works with only:

- A fork of this repo
- A valid `ZB_TOKEN` for `pkg.zerobias.org`
- The tools listed in [Prerequisites](#prerequisites) below

## Why this guide exists

Two recent PRs were merged in a structurally-broken state because the signals contributors (and their AI agents) trusted looked green but did not actually validate the schema:

1. `npm run validate` passed, even though class YAMLs referenced fields that had no corresponding `fields/*.yml`. The validate script does not check field references — see [The three validation layers](#the-three-validation-layers).
2. CI showed no failures, because the PR was unlabeled and the dataloader job was **skipped** rather than run. Skipped is not the same as passed — see [The `approved` label CI gate](#the-approved-label-ci-gate).

Following the steps below catches both classes of error before you push.

## The three validation layers

Schemas are validated at three different layers, each catching different problems. **All three matter.**

| Layer | Command | What it checks | Speed | Required before push? |
|---|---|---|---|---|
| **1. Package structure** | `npm run validate` | `package.json` shape, `catalog.yml` shape, `.npmrc` presence, naming consistency between npm name / catalog package / directory / product dependency | seconds | Yes |
| **2. Local dataloader** | `dataloader --content-dev …` against a local Supabase scratch DB | Field references resolve, `linkTo` targets exist, bidirectional links are consistent, enum values are ALL_CAPS, types are valid, imports cover everything you extend | ~30s–2m | **Yes** |
| **3. CI dataloader** | Triggered automatically once a maintainer adds the `approved` label | Same dataloader, but run against a **Neon branch cloned from `content-master`** with production-shape data | minutes | Triggered for you; you cannot run it locally |

Layer 1 alone will let many real bugs through. Layer 2 is the smallest local check that catches what production cares about. Layer 3 is authoritative but only runs when a maintainer opts you in.

## Prerequisites

Install once per machine:

- **Node.js** — match the version implied by `package.json` `engines` if specified, otherwise the current LTS.
- **Docker Desktop** (or any local Docker daemon) — the local scratch database runs in a container.
- **`ZB_TOKEN`** — exported in your shell so `npm install` can fetch private `@zerobias-com` and `@zerobias-org` packages from `https://pkg.zerobias.org`. Set this in your shell profile:
  ```sh
  export ZB_TOKEN=<your-pkg.zerobias.org-token>
  ```
- **The dataloader CLI**, installed globally:
  ```sh
  npm i -g @zerobias-com/platform-dataloader@latest
  ```

Verify the install:

```sh
dataloader --help
```

## Local dataloader setup

Spin up the local scratch database (Supabase, Postgres 17, port `15432`, database `content_dev`) in a separate terminal:

```sh
npx @zerobias-org/util-content-dev-schema
```

Leave that process running while you validate. To tear it down later, stop it with `Ctrl-C` and follow any cleanup instructions it prints.

Export the connection environment variables that the dataloader will use:

```sh
export PGHOST=localhost
export PGPORT=15432
export PGUSER=postgres
export PGPASSWORD=welcome
export PGDATABASE=content_dev
export PGSSLMODE=disable
```

These values are specific to the local scratch DB and are deliberately different from CI (see [How local differs from CI](#how-local-differs-from-ci)).

## Running the dataloader on your package

From within your schema package directory:

```sh
cd package/<vendor>/<code>
npm install
npm run validate
dataloader --content-dev --skip-pgboss --skip-dynamo -d ./
```

A successful run ends with a line like:

```
Importer finished successfully
```

and exits with status `0`. Anything else — non-zero exit code, an error stack, a "missing field" message, a "class not found" message — is a real failure that must be fixed before pushing.

A typical schema runs in well under two minutes locally. If it hangs longer than that, the scratch DB or a missing dependency is the usual cause.

## What the dataloader catches that `npm run validate` doesn't

`npm run validate` only checks package structure. The dataloader actually loads your YAML into the graph and rejects it on:

- **Missing field YAMLs** — a class declares `field: repository.fullName` but `fields/repository.fullName.yml` does not exist in your package or any imported package.
- **Bad `linkTo` targets** — a property links to a class that is not defined in your schema or any package listed in `zerobias.imports`.
- **One-sided bidirectional links** — class `A` links to `B` but `B` has no reciprocal link back to `A`, or the inverse names disagree.
- **Type mismatches** — a field's declared type does not match how the property is used (e.g. `string` field referenced as a numeric property).
- **Lowercase enum values** — enum values must match `[A-Z][A-Z0-9_]*`. The validate script does not enforce this; the dataloader rejects it at load time.
- **Missing imports** — extending `Object`, `File`, `Element`, or any base class without listing the providing package in `zerobias.imports` (typically `zerobias.zerobias.platform.schema` and/or `zerobias.zerobias.base.schema`).

All of the above show up as a failed local dataloader run with a clear error message identifying the offending file.

## How local differs from CI

Local validation is a **fast smoke test**, not a CI parity check.

| Aspect | Local | CI |
|---|---|---|
| Database | Supabase scratch container | Neon branch cloned from `content-master` |
| Postgres version | 17 | 15/16 |
| Port | `15432` | `5432` |
| Database name | `content_dev` | `zerobias` |
| `PGSSLMODE` | `disable` | `require` |
| Baseline data | Empty / minimal | Production-shape content |
| Dataloader flags | `--content-dev --skip-pgboss --skip-dynamo` | Different set of flags |
| Trigger | You, manually | Automatic on `synchronize` once `approved` label is present |
| Class IDs | Same as CI / prod (deterministic UUID v5 from YAML content) | Same as local / prod |

Implications:

- **Local passing does not guarantee CI will pass.** Production-shape data sometimes surfaces conflicts (e.g., an existing class your new schema collides with) that an empty scratch DB cannot.
- **Local failing is almost always a real bug.** Fix it before pushing — there is no scenario where a clean CI run "rescues" a local failure caused by a missing field or bad link.
- **Class IDs are deterministic.** Each class gets a UUID v5 derived from its YAML content, so the ID your local dataloader assigns is the same ID CI and production will assign. App-side code can register class ID constants from a successful local run and trust them across environments — as long as the YAML doesn't change before merge.
- The full Neon-branch CI is the authoritative gate. It runs **only when a maintainer adds the `approved` label** to your PR (see next section).

## The `approved` label CI gate

The CI workflow that runs the dataloader is gated on **two conditions**, both of which must be true:

1. The pull request has the **`approved`** label.
2. The triggering event is `labeled` (the moment the label was added) or `synchronize` (a new push to a branch that already has the label).

If either condition is unmet, the dataloader job is **skipped**.

### What the PR check status means

| Status on PR | Meaning |
|---|---|
| `Test` job is **green / success** | The dataloader ran against a Neon branch and passed. Safe to merge. |
| `Test` job is **red / failure** | The dataloader ran and failed. Read the logs and fix. |
| `Test` job is **skipped** (or absent from the check list) | **The dataloader did not run.** This is not a pass. Do not interpret it as one. |

### Who can add the label

Only ZeroBias maintainers can add the `approved` label. External contributors cannot self-approve. The expected flow is:

1. You open the PR against `dev`.
2. A maintainer reviews the changes.
3. The maintainer adds the `approved` label.
4. CI runs. The job appears as `Test` in the PR's checks.
5. If CI is green, the maintainer merges.

If you push new commits after the label is added, CI re-runs automatically (the push is a `synchronize` event). You do not need a re-label.

If CI never appears at all after the label is added, the most common cause is that the label was added on `opened` rather than via `labeled`/`synchronize`. Push an empty commit (`git commit --allow-empty -m "ci: trigger"`) to force a `synchronize` event.

## Common failure modes

Top five issues seen on third-party PRs, with concrete symptoms and fixes.

### 1. Class references a field that has no `fields/*.yml`

**Symptom:** Local dataloader prints something like `field "engagement.budgetType" not found` and exits non-zero. `npm run validate` was clean.

**Fix:** Either create `fields/engagement.budgetType.yml` with the correct `type` and `description`, or remove the reference from the class.

### 2. `linkTo` points to a class that does not exist or is not imported

**Symptom:** Dataloader rejects with `unknown class "Foo"` or similar.

**Fix:** Confirm the target class exists either in your `classes/` directory or in a package you have listed in `zerobias.imports`. If it lives in another schema, add that schema to your `dependencies` and to `zerobias.imports`.

### 3. Bidirectional link defined on only one side

**Symptom:** Dataloader complains about a missing inverse, or the link silently fails to materialize after load.

**Fix:** When `Engagement` has `bids -> Bid[]`, `Bid` must also declare the reciprocal `engagement -> Engagement` with matching inverse names. Define both sides explicitly.

### 4. Enum values written in lowercase or mixed case

**Symptom:** Dataloader rejects the enum at load with a regex error like `value "active" does not match [A-Z][A-Z0-9_]*`.

**Fix:** Rename the value to ALL_CAPS (`ACTIVE`, `IN_PROGRESS`, `NOT_APPLICABLE`). The validate script does not catch this — only the dataloader does.

### 5. Missing entry in `zerobias.imports`

**Symptom:** Dataloader cannot resolve a base class such as `Object`, `File`, or `Element`, even though the dependency is listed in `package.json`.

**Fix:** `dependencies` and `zerobias.imports` are both required. Add the providing package's catalog name (typically `zerobias.zerobias.platform.schema` and `zerobias.zerobias.base.schema`) to the `imports` array.

## Pre-push checklist

Before opening a PR:

- [ ] `npm install` succeeds in your package directory.
- [ ] `npm run validate` exits `0`.
- [ ] Local scratch DB is running (`npx @zerobias-org/util-content-dev-schema`).
- [ ] Connection env vars are exported (`PGHOST`, `PGPORT=15432`, `PGUSER`, `PGPASSWORD`, `PGDATABASE=content_dev`, `PGSSLMODE=disable`).
- [ ] `dataloader --content-dev --skip-pgboss --skip-dynamo -d ./` ends with `Importer finished successfully` and exit code `0`.
- [ ] Commit follows Conventional Commits (`feat:`, `fix:`, `docs:`, …).
- [ ] PR is opened **cross-fork** against `zerobias-org/schema:dev`, not against your fork's `dev`. From a fork checkout, the explicit command is:
  ```sh
  gh pr create \
    --repo zerobias-org/schema \
    --base dev \
    --head <your-fork-owner>:<your-branch> \
    --title "..." \
    --body "..."
  ```
  Without `--repo`, `gh` defaults to your fork and the PR will not reach upstream.
- [ ] PR description notes that local dataloader passed, so a maintainer knows it is safe to add the `approved` label.

After the PR is open, wait for a maintainer to add `approved`, then watch the `Test` check. Treat skipped as "did not run," not as "passed."
