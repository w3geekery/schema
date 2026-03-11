# CLAUDE.md - ZeroBias-Org Schema Repository

This file provides guidance to Claude Code (claude.ai/code) when working with schema definitions in this repository.

**NOTE:** For best results, run Claude Code from meta-repo root (`~/zerobias`) to ensure access to all platform context and cross-module documentation.

## Overview

This is a Lerna-managed monorepo containing **open-source AuditgraphDB schema packages** under the `@zerobias-org` organization. Schema packages define object types (classes, interfaces, fields, documents, enums) that are loaded into AuditgraphDB by the dataloader.

**Repository Role:** Community-contributed schema definitions for AuditgraphDB
**Closed-source counterpart:** `auditlogic/schema` (`@auditlogic` scope)

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
When working in a specific schema package (e.g., `package/zerobias/schemas/mcpservers/`):
- **Validate schema**: `npm run validate`
- **Correct dependencies**: `npm run correct:deps`

## Repository Structure

### Monorepo Structure
- **`package/`**: Contains all schema packages organized by vendor/code
  - Structure: `package/{vendor}/{code}/`
  - Example: `package/zerobias/schemas/agentskills/`, `package/zerobias/schemas/mcpservers/`
- **`scripts/`**: Build and utility scripts (validate.ts, createNewSchema.sh, etc.)
- **`bundle/`**: Bundled package artifacts

### Schema Package Structure
Each schema package follows this structure:
```
package/{vendor}/{code}/
├── package.json          # @zerobias-org/schema-{vendor}-{code}
├── catalog.yml           # Schema catalog entry
├── .npmrc                # Registry configuration
├── classes/              # AuditgraphDB class definitions (YAML) - PascalCase
├── interfaces/           # Interface definitions (YAML) - PascalCase
├── fields/               # Field definitions (YAML) - camelCase dot-notation
├── documents/            # Document type definitions (optional, YAML)
└── enums/                # Enum type definitions (optional, YAML)
```

### Technology Stack
- **Lerna 9.x**: Monorepo management and versioning (independent mode)
- **Nx 22.x**: Build system and caching
- **TypeScript/tsx**: Validation scripts and tooling
- **YAML**: Schema definition format
- **Husky**: Git hooks for commit validation

---

## Schema Definition Reference

### Classes (`classes/`)

Concrete classes define AuditgraphDB object types. They represent real objects collected from external systems.

**Filename:** PascalCase matching class name (e.g., `McpServer.yml`)

```yaml
description: "An MCP Server definition"                # REQUIRED
extends:                                               # Optional (defaults to 'Object')
  - Element                                            # Can extend INTERFACES only (not other classes)
icon: images/classes/vendor/ClassName.svg               # Optional icon URL
shared: false                                          # Optional (default: false)
tags:                                                  # Optional tags for categorization
  - query-folder.servers
properties:                                            # Optional (must be array if present)
  - vendor:
    field:                                             # Inline field definition
      type: string
      description: "Vendor name"
  - license:
    field:
      type: string
      description: "License name or reference"
  - toolCount:
    field:
      type: integer
      description: "Number of tools"
  - members:                                           # Multi-valued link
    multi: true
    linkTo: McpTool
viewProperties:                                        # Optional UI display config
  "Name":
    jsonata: name                                      # JSONata expression
    sort: name                                         # Sortable column
  "Vendor":
    jsonata: vendor
  "Tools":
    jsonata: $count(tools)                             # Computed property
```

**Class Rules (enforced by dataloader):**
- `description` is **required**
- `properties` must be an **array** if present
- Class names are **globally unique**
- Classes can only extend **interfaces** (not other concrete classes)
- If no `extends`, defaults to extending `Object` (for non-platform schemas)
- Property names must be **unique** within the class (including inherited properties)
- Cannot overload an extended class's property field with a link
- Cannot `skip` and `deprecate` simultaneously

### Interfaces (`interfaces/`)

Interfaces define shared property contracts that classes and other interfaces can extend.

**Filename:** PascalCase matching interface name (e.g., `Account.yml`)

```yaml
description: "A user or system account"      # REQUIRED
extends:
  - Principal                                 # Can extend OTHER INTERFACES only
viewProperties:
  "Name":
    jsonata: name
    sort: name
properties:
  - login:
    field: account.login
  - email:
    field: email
    multi: true
  - identity:                                 # Link with multiple target types
    multi: true
    linkTo:
      - FederatedIdentity.id
      - FederatedIdentity.email
```

**Interface Rules (enforced by dataloader):**
- `description` is **required**
- Interface names are **globally unique**
- Interfaces can extend **other interfaces** only (not concrete classes)
- **No circular extends chains** (loop detection enforced)
- Property names must be **unique** within the interface

### Fields (`fields/`)

Fields define atomic, reusable property types.

**Filename:** camelCase with dot-notation: `{parentType}.{fieldName}.yml` (e.g., `account.login.yml`)

```yaml
description: "The login identifier"    # Optional (defaults to field name)
displayName: "Login"                   # Optional (defaults to field name)
type: "string"                         # REQUIRED
keyed: true                            # Optional (default: false) - searchable
indexed: true                          # Optional (default: true) - keyed overrides to true
reserved: false                        # Optional (default: false) - protected field
defaultValue: "unknown"                # Optional
example: "admin@company.com"           # Optional
```

**Supported Types:** `string`, `boolean`, `number`, `integer`, `date`, `datetime`

**Field Rules (enforced by dataloader):**
- `type` is **required** and must be non-empty
- Field names are **globally unique**
- Cannot be named `enum` (use enums/ directory instead)
- `keyed` and `indexed` must be boolean if specified
- `keyed: true` automatically sets `indexed: true`
- Reserved fields cannot also be keyed

### Enums (`enums/`)

Enums define enumerated value sets.

**Filename:** camelCase with dot-notation: `{parentType}.{enumName}.yml`

```yaml
description: "Asset Status"                # Optional
displayName: "Asset Status"                # Optional
values:                                    # REQUIRED (must be non-empty array)
  - ACTIVE: "Asset is active and in use"
  - AVAILABLE: "Asset is available"
  - RETIRED: "Asset is retired"
```

**Enum Rules (enforced by dataloader):**
- `values` array is **required** and cannot be empty
- Values can be simple strings or `{KEY: description}` objects
- Value names must be **ALL CAPS** with underscores only (`[A-Z][A-Z0-9_]*`)
- Value names must start with a **letter or underscore**
- Values cannot **repeat** within the same enum
- Enum names are **globally unique**

### Documents (`documents/`) - Optional

Documents define complex nested object structures.

```yaml
description: "Organization billing plan"
displayName: "Plan"
properties:                                  # REQUIRED (must be array)
  - company:
    field:
      type: string
  - seats:
    field:
      type: int
```

**Document Rules:** Properties must be an array; top-level names cannot repeat; document links require `uniLink: true`.

### Deprecated File (`deprecated.yml`)

Lists deleted classes/fields/enums/documents for dataloader cleanup.

```yaml
classes:
  - OldClassName
fields:
  - old.fieldName
enums:
  - old.enumName
```

---

## Link Field Configuration

Links create graph relationships between classes. They are defined within `properties` arrays.

### Link Patterns

```yaml
properties:
  # Simple link (bidirectional by default)
  - enterprise:
    linkTo: GitHubEnterprise

  # Multi-valued link
  - members:
    multi: true
    linkTo: GitHubUser

  # Bidirectional link (explicit both sides)
  - parent:
    linkTo: CAPEC.id.children
  - children:
    multi: true
    linkTo: CAPEC.id.parent

  # Multiple target types
  - identity:
    multi: true
    linkTo:
      - FederatedIdentity.id
      - FederatedIdentity.email

  # Unidirectional link
  - cpeProduct:
    linkTo: CpeProduct.versions
    uniLink: true

  # Temporal relationship
  - assignedTo:
    linkTo: ITAssetManagementUser
    t3: issuedDate

  # Deferred link (resolved in future schema load)
  - externalRef:
    linkTo: ExternalClass
    defered: true
```

### Link Rules (enforced by dataloader)
- `linkTo` as array **cannot** use `patternMatch`
- `linkTo` array **cannot** be empty; items must include a **period**
- Property names in array **cannot repeat**
- Both sides of bidirectional links **must match**
- `t3` fields must exist and match on both sides
- If no match found and `defered` is not true, throws an error

---

## Property Definition Patterns

### Reference Existing Field
```yaml
- login:
  field: account.login              # References fields/account.login.yml
```

### Inline Field Definition
```yaml
- kev:
  field:
    type: boolean                   # Required for inline
    description: "Known Exploited"  # Required for inline
```

### Property-to-Field Preference Order
1. **Use base schema fields** when possible (e.g., `email`, `url`, `name`)
2. **Inline field** if unique to this class and used only once
3. **Package field** (`fields/`) if used in multiple classes within the package
4. **Enums and documents** must always be declared in their directories

---

## View Properties (Dashboard Configuration)

```yaml
viewProperties:
  "Column Header":
    jsonata: propertyName           # JSONata expression
    sort: propertyName              # Optional: enables sorting
  "Computed":
    jsonata: $count(members)        # JSONata functions supported
```

**Rules:** Sort column max 3 levels deep; must exist in class or extended schema.

---

## Package Configuration

### package.json

Use `"zerobias"` as the config key for all packages.

```json
{
  "name": "@zerobias-org/schema-{vendor}-{code}",
  "description": "Schemas for {description}.",
  "version": "1.0.0-rc.1",
  "zerobias": {
    "dataloader-version": "1.0.0",
    "import-artifact": "schema",
    "package": "{vendor}.{code}.schema",
    "imports": [
      "zerobias.zerobias.platform.schema",
      "zerobias.zerobias.base.schema"
    ]
  },
  "files": [
    "classes/**",
    "interfaces/**",
    "fields/**",
    "documents/**",
    "enums/**",
    "catalog.yml"
  ],
  "scripts": {
    "validate": "tsx ../../../../scripts/validate.ts",
    "correct:deps": "tsx ../../../../scripts/correctDeps.ts"
  },
  "dependencies": {
    "@zerobias-org/product-{vendor}-{code}": "^1.0.0",
    "@zerobias-org/schema-zerobias-zerobias-base": "^2.0.0",
    "@zerobias-com/schema-zerobias-zerobias-platform": "^1.0.0"
  }
}
```

### catalog.yml

```yaml
Schema:
  name: "Schema Display Name"
  package: "{vendor}.{code}.schema"
  description: |-
    AuditgraphDB schema for ...
```

**Required fields:** `name`, `package`, `description` (all must be non-placeholder values)

### Naming Conventions

| Item | Format | Example |
|------|--------|---------|
| NPM package | `@zerobias-org/schema-{vendor}-{code}` | `@zerobias-org/schema-zerobias-schemas-mcpservers` |
| Catalog package | `{vendor}.{code}.schema` | `zerobias.schemas.mcpservers.schema` |
| Directory | `package/{vendor}/{code}/` | `package/zerobias/schemas/mcpservers/` |

## Validation & Testing

### Static Validation (`scripts/validate.ts`)

```bash
# Validate all packages
npm run validate

# Validate a single package
cd package/{vendor}/{code} && npm run validate
```

Checks:
- Package name matches `@zerobias-org/schema-*`
- `zerobias` (or `auditmation`) section exists with `import-artifact: "schema"`, `package`, `dataloader-version`
- `catalog.yml` has `Schema` section with `name`, `package`, `description` (non-placeholder values)
- `.npmrc` file exists
- At least one of `classes/`, `interfaces/`, or `fields/` directories exists

### Dataloader Validation

Run the dataloader against a schema package directory to validate all YAML definitions:

```bash
dataloader -d package/{vendor}/{code} --skip-pgboss
```

This validates all class/interface/field/enum/document definitions, inheritance chains, link matching, property uniqueness, field types, enum format, and viewProperties.

### Common Validation Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `properties is not an array` | Properties defined as object | Use array syntax: `- propName:` |
| `description is missing` | No description in class/interface | Add `description: "..."` |
| `extended interface does not exist` | Typo in extends | Check interface name spelling |
| `extends logic loop found` | Circular inheritance | Remove circular reference |
| `cannot overload extended properties field with a link` | Link uses inherited property name | Rename the link property |
| `No matching link` | Bidirectional link missing other side | Add link on target class or use `uniLink: true` or `defered: true` |
| `Enumeration value must start with letter` | Lowercase or numeric enum value | Use ALL_CAPS format |
| `Field type not specified` | Missing type in field | Add `type: string` (or other type) |

---

## Development Workflow

### Creating a New Schema Package
1. **Verify dependencies** - Vendor and product must exist in the platform
2. **Create directory:** `mkdir -p package/{vendor}/{code}`
3. **Use script:** `scripts/createNewSchema.sh package/{vendor}/{code}` (copies templates, generates UUID)
4. **Replace placeholders** in package.json and catalog.yml: `{vendor}`, `{code}`, `{name}`, `{description}`
5. **Create schema files** in `classes/`, `interfaces/`, `fields/`
6. **Install:** `cd package/{vendor}/{code} && npm install`
7. **Validate:** `npm run validate`

### Inheritance Design Guidelines
- **Use base interfaces** from `zerobias.zerobias.base` (Account, Asset, Repository, Application, etc.)
- **Create vendor-specific interfaces** for properties shared across multiple classes from the same vendor
- **Multiple inheritance** supported - combine base + vendor interfaces
- **Extending `Element`** base class enables framework linking without additional schema changes

### Dependencies
- Schema packages depend on their product package: `@zerobias-org/product-{vendor}-{code}`
- Import platform schema for base classes via `zerobias.imports` array
- Dependency chain: `Vendor → [Suite] → [Product] → Schema → CollectorBot → Pipeline`

**CRITICAL:** Vendor is required; suite and product are optional. Check/create dependencies first.

## TypeScript Packages (`-ts`)

On publish, each schema package automatically generates a companion TypeScript package with typed interfaces. These are published as a separate NPM package with a `-ts` suffix.

- **Naming:** `@zerobias-org/schema-{vendor}-{code}-ts` (e.g., `@zerobias-org/schema-zerobias-schemas-mcpservers-ts`)
- **Generated during:** `nx:prepublish` → `scripts/prepublish.sh`
- **Published during:** `scripts/postpublish.sh` (same version as the schema package)
- **Contents:** TypeScript interfaces generated by `@zerobias-com/platform-schema-ts-generator`
- **Skipped** when `zerobias.deprecated: true`

These `-ts` packages are consumed by collector bots and other TypeScript code that needs type-safe access to schema objects.

## Commit and Versioning
- Follow Conventional Commits: `<type>(<scope>): <subject>`
- Types: feat, fix, docs, style, refactor, perf, test, chore
- Lerna handles versioning and changelog generation
- No manual version bumps in pull requests
- Schema versions start at `1.0.0-rc.1`

## Authentication
- Set `ZB_TOKEN` environment variable for NPM registry authentication
- Packages publish to ZeroBias Package Registry: `https://pkg.zerobias.org/`

## Important Notes
- Always run `npm install` in root directory first to setup husky hooks
- PRs must target the `dev` branch (not `main`)
- Validation scripts ensure schema integrity before publication
- Use `"zerobias"` config key in package.json (dataloader supports both `zerobias` and `auditmation`)

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

## Related Documentation
- **Meta-repo CLAUDE.md:** `../../CLAUDE.md`
- **Architecture.md:** `../../Architecture.md`
- **ContentArtifacts.md:** `../../ContentArtifacts.md`
- **Vendor repo:** `../vendor/CLAUDE.md`
- **Product repo:** `../product/`
- **Collector bot repo:** `../collectorbot/`
- **Auditlogic schema (closed-source):** `../../auditlogic/schema/CLAUDE.md`
- **Dataloader processor:** `../../com/platform/dataloader/src/processors/schemas/`
