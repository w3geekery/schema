# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Lerna-managed monorepo containing AuditgraphDB schema packages under the `@zerobias-org` organization. Schema packages define object types (classes, interfaces, fields, documents, enums) that are loaded into AuditgraphDB by the dataloader.

**NOTE:** For best results, run Claude Code from meta-repo root (`~/zerobias`) to ensure access to all platform context and cross-module documentation.

## Common Development Commands

### Setup and Installation
- **Initial setup**: `npm install` (run in root directory first to setup husky hooks)
- **Install dependencies**: `npm install` (in individual package directories)

### Building and Testing
- **Validate all schemas**: `npm run validate`
- **Clean build artifacts**: `npm run clean`
- **Full reset**: `npm run reset` (clean, reinstall)

### Lerna Operations
- **Dry run version bump**: `npm run lerna:dry-run`
- **Version packages**: `npm run lerna:version`

### Individual Package Commands
When working in a specific schema package (e.g., `package/github/github/`):
- **Validate schema**: `npm run validate`
- **Correct dependencies**: `npm run correct:deps`

## Repository Architecture

### Monorepo Structure
- **`package/`**: Contains all schema packages organized by vendor/code
  - Structure: `package/{vendor}/{code}/`
  - Example: `package/github/github/`, `package/agentskills/agentskills/`
- **`scripts/`**: Build and utility scripts
- **`templates/`**: Template files for creating new schema packages
- **`bundle/`**: Bundled package artifacts

### Schema Package Structure
Each schema package follows this structure:
```
package/{vendor}/{code}/
├── package.json          # @zerobias-org/schema-{vendor}-{code}
├── catalog.yml           # Schema catalog entry
├── .npmrc                # Registry configuration
├── classes/              # AuditgraphDB class definitions (YAML)
├── interfaces/           # Interface definitions (YAML)
├── fields/               # Field definitions (YAML)
├── documents/            # Document type definitions (optional)
└── enums/                # Enum type definitions (optional)
```

### Technology Stack
- **Lerna 9.x**: Monorepo management and versioning (independent mode)
- **Nx 22.x**: Build system and caching
- **TypeScript/tsx**: Validation scripts and tooling
- **YAML**: Schema definition format
- **Husky**: Git hooks for commit validation

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

```yaml
# enums/team.privacy.yml
description: The level of privacy this team should have.
displayName: Privacy
values:
  - secret: 'Only visible to organization owners and members of this team.'
  - closed: 'Visible to all members of this organization.'
```

## Validation

### Validation Script (`scripts/validate.ts`)
The validation script checks:
- Package name matches `@zerobias-org/schema-*`
- `zerobias` (or `auditmation`) section exists with `import-artifact: "schema"`
- `catalog.yml` has `Schema` section with `name`, `package`, `description`
- `.npmrc` file exists
- At least one of `classes/`, `interfaces/`, or `fields/` directories exists

### Package Naming
- Package names: `@zerobias-org/schema-{vendor}-{code}`
- Catalog package: `{vendor}.{code}.schema`
- Config key: `zerobias` (not `auditmation` for new packages)

## Development Workflow

### Creating a New Schema Package
1. Create directory: `mkdir -p package/{vendor}/{code}`
2. Copy templates: Use `scripts/createNewSchema.sh` or copy from `templates/`
3. Replace placeholders: `{vendor}`, `{code}`, `{name}`, `{description}`
4. Create schema files in `classes/`, `interfaces/`, `fields/`
5. Install: `cd package/{vendor}/{code} && npm install`
6. Validate: `npm run validate`

### Dependencies
- Schema packages depend on their product package: `@zerobias-org/product-{vendor}-{code}`
- Schema packages import platform schema for base classes: `@auditmation/schema-auditmation-auditmation-platform`
- The `zerobias.imports` array lists schema packages providing base classes

## Commit and Versioning
- Follow Conventional Commits: `<type>(<scope>): <subject>`
- Types: feat, fix, docs, style, refactor, perf, test, chore
- Lerna handles versioning and changelog generation
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

## Important Notes
- Always run `npm install` in root directory first to setup husky hooks
- PRs must target the `dev` branch (not `main`)
- Schema versions start at `1.0.0-rc.1` and are managed by Lerna
- Validation scripts ensure schema integrity before publication
- Schema packages use the `zerobias` config key (dataloader supports both `zerobias` and `auditmation`)
- Extending `Element` base class enables framework linking without schema changes

## Related Documentation
- **Meta-repo CLAUDE.md:** `../../CLAUDE.md`
- **Architecture.md:** `../../Architecture.md`
- **Vendor repo:** `../vendor/CLAUDE.md`
- **Product repo:** `../product/`
- **Collector bot repo:** `../collectorbot/`
- **Existing schema examples:** `../../auditlogic/schema/package/` (e.g., `github/github/`)
