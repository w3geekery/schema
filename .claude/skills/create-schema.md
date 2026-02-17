# Create Schema Skill

Create AuditgraphDB schema packages from ZeroBias tasks with automatic dependency resolution and proper task management.

## Trigger

```
/create-schema [task-id]
```

**Arguments:**
- `task-id` (optional): ZeroBias task UUID or task name. If not provided, will prompt for input.

## Examples

```
/create-schema bbd73958-f3f6-4ec7-a2ed-79cb105c9c19
/create-schema "Create schema: github/github"
/create-schema
```

---

## Workflow

### Step 1: Get Task Details

```javascript
// If UUID provided
const task = zerobias_execute("platform.Task.get", { id: taskId })

// If task name provided (search)
const results = zerobias_execute("portal.Task.search", {
  searchTaskBody: { search: "schema name" }
})
const task = results.items.find(t => t.name.includes("schema"))
```

**Task code is NOT searchable** - use UUID or task name.

### Step 2: Extract Schema Information

| Field | Source | Example |
|-------|--------|---------|
| **Task ID** | `task.id` | `bbd73958-f3f6-4ec7-a2ed-79cb105c9c19` |
| **Task Code** | `task.code` | `contextDev-20` |
| **Vendor Code** | Parse from name | `github` |
| **Schema Code** | Parse from name | `github` |
| **Schema Name** | Parse from name | `GitHub Schema` |
| **Artifact Type** | `task.customFields.artifactType` | `schema` |
| **Branch Name** | `task.customFields.branchName` | `feat/schema-github-github` |
| **Repo URL** | `task.customFields.repoUrl` | `https://github.com/zerobias-org/schema` |

**Parse schema info from task name:**
```javascript
// Task name format: "Create schema: {vendor}/{code} ({name})"
const match = task.name.match(/Create schema:\s*(\S+)\/(\S+)\s*\(([^)]+)\)/)
const vendorCode = match[1]  // "github"
const schemaCode = match[2]  // "github"
const schemaName = match[3]  // "GitHub Schema"

// Alternative format: "Create schema: {vendor}/{code}"
const matchSimple = task.name.match(/Create schema:\s*(\S+)\/(\S+)/)
const vendorCode = matchSimple[1]
const schemaCode = matchSimple[2]
```

**Parse additional info from task description:**
```javascript
// Task description may contain:
// - Source URLs for schema design reference
// - Class names and fields to include
// - Which base classes to extend
// - Which platform schema to import

const urlMatch = task.description.match(/https?:\/\/[^\s]+/)
const sourceUrl = urlMatch ? urlMatch[0] : null
```

### Step 3: Assign and Transition to In Progress

**IMPORTANT:** Set required fields BEFORE applying transition.

```javascript
// Get your party ID
const party = zerobias_execute("platform.Party.getMyParty", {})

// Update task with required fields and transition
zerobias_execute("platform.Task.update", {
  id: task.id,
  updateTask: {
    assigned: party.id,  // Party ID, NOT principal ID
    customFields: {
      artifactType: "schema",
      repoUrl: "https://github.com/zerobias-org/schema",
      branchName: `feat/schema-${vendorCode}-${schemaCode}`
    },
    transitionId: "7f140bbe-4c10-54ac-922c-460c66392fad"  // Start
  }
})
```

**Transition Required Fields:**

| Transition | Required Fields | Required Custom Fields |
|------------|-----------------|------------------------|
| Start | assigned | repoUrl, branchName |
| Peer Review | assigned, approvers | - |
| Accept | assigned | fixVersion |

### Step 4: Add Starting Comment

```javascript
zerobias_execute("platform.Task.addComment", {
  id: task.id,
  newTaskComment: {
    commentMarkdown: `**Started:** Creating schema package.

**Task:** ${task.code}
**Vendor:** ${vendorCode}
**Schema:** ${schemaCode}
**Branch:** feat/schema-${vendorCode}-${schemaCode}
**Repo:** https://github.com/zerobias-org/schema`
  }
})
```

### Step 5: Check Dependencies (MANDATORY)

**CRITICAL:** Schemas are on the data workflow. Vendor is required; suite and product are optional.

```
Standards workflow:  vendor → [suite] → [product] → framework/standard/benchmark → crosswalk
Data workflow:       vendor → [suite] → [product] → schema → collectorbot → pipeline
```

```javascript
// 1. Check vendor exists
const vendors = zerobias_execute("portal.Vendor.search", {
  searchVendorBody: { search: vendorCode }
})
const vendorExists = vendors.items.some(v =>
  v.code?.toLowerCase() === vendorCode.toLowerCase()
)

// 2. Check product exists
const products = zerobias_execute("portal.Product.search", {
  searchProductBody: { search: `${vendorCode} ${schemaCode}` }
})
const productExists = products.items.some(p =>
  p.vendorCode?.toLowerCase() === vendorCode.toLowerCase() &&
  p.code?.toLowerCase() === schemaCode.toLowerCase()
)

if (!vendorExists || !productExists) {
  // STOP - Dependencies must be created first
  // See: docs/orchestration/TASK_MANAGEMENT.md#dependency-management
  // 1. Create vendor subtask (if missing)
  // 2. Create product subtask (if missing)
  // 3. Complete dependencies first
  // 4. Then resume this task
}
```

**If dependencies are missing:** See [TASK_MANAGEMENT.md](../../../docs/orchestration/TASK_MANAGEMENT.md#dependency-management) for the subtask creation and skill invocation workflow.

### Step 6: Check if Schema Already Exists

```javascript
// Search for existing schema package in catalog
// Schema packages don't have a dedicated portal search, so check npm registry
```

```bash
# Check if package already exists
npm view @zerobias-org/schema-${vendorCode}-${schemaCode} version 2>/dev/null
```

### Step 7: Create Git Branch

```bash
cd /path/to/zerobias-org/schema
git checkout main
git pull origin main
git checkout -b feat/schema-{vendorCode}-{schemaCode}
```

### Step 8: Create Schema Package Structure

```bash
# Create package directory
mkdir -p package/{vendorCode}/{schemaCode}
cd package/{vendorCode}/{schemaCode}

# Create schema subdirectories
mkdir -p classes interfaces fields
```

**Required files:**

```
package/{vendorCode}/{schemaCode}/
├── package.json          # @zerobias-org/schema-{vendor}-{code}
├── catalog.yml           # Schema catalog entry
├── .npmrc                # Registry configuration
├── classes/              # Class definitions (YAML)
│   └── {ClassName}.yml
├── interfaces/           # Interface definitions (YAML)
│   └── {InterfaceName}.yml
└── fields/               # Field definitions (YAML)
    └── {className}.{fieldName}.yml
```

**Optional directories:**

```
├── documents/            # Document type definitions
│   └── {className}.{docName}.yml
└── enums/                # Enum type definitions
    └── {className}.{enumName}.yml
```

### Step 9: Create package.json

```json
{
  "name": "@zerobias-org/schema-{vendorCode}-{schemaCode}",
  "version": "1.0.0-rc.1",
  "description": "Schema for {Schema Name}",
  "author": "team@zerobias.com",
  "license": "ISC",
  "type": "module",
  "repository": {
    "type": "git",
    "url": "git@github.com:zerobias-org/schema.git",
    "directory": "package/{vendorCode}/{schemaCode}/"
  },
  "scripts": {
    "correct:deps": "tsx ../../../scripts/correctDeps.ts",
    "validate": "tsx ../../../scripts/validate.ts"
  },
  "publishConfig": {
    "registry": "https://npm.pkg.github.com/"
  },
  "files": [
    "classes/**",
    "interfaces/**",
    "fields/**",
    "documents/**",
    "enums/**",
    "catalog.yml",
    "README.md"
  ],
  "dependencies": {
    "@zerobias-org/product-{vendorCode}-{schemaCode}": "latest",
    "@auditmation/schema-auditmation-auditmation-platform": "latest"
  },
  "zerobias": {
    "dataloader-version": "1.0.0",
    "import-artifact": "schema",
    "package": "{vendorCode}.{schemaCode}.schema",
    "imports": [
      "auditmation.auditmation.platform.schema"
    ]
  }
}
```

**CRITICAL:**
- Package name format: `@zerobias-org/schema-{vendorCode}-{schemaCode}`
- Must depend on the product package: `@zerobias-org/product-{vendorCode}-{schemaCode}`
- Must depend on platform schema for base classes (Element, etc.)
- `zerobias` section must have `import-artifact: "schema"`
- `imports` array lists schema packages that provide base classes

### Step 10: Create catalog.yml

```yaml
Schema:
  name: "{Schema Name}"
  package: "{vendorCode}.{schemaCode}.schema"
  description: |-
    AuditgraphDB schema for {Schema Name}
```

**CRITICAL:**
- Must have a `Schema` top-level key
- `name` must not be template placeholder `{name}`
- `package` must match `zerobias.package` in package.json
- `description` must not be template placeholder `{description}`

### Step 11: Create .npmrc

```
@auditlogic:registry=https://npm.pkg.github.com/
@zerobias-com:registry=https://npm.pkg.github.com/
//npm.pkg.github.com/:_authToken=${NPM_TOKEN}
@zerobias-org:registry=https://pkg.zerobias.org/
//pkg.zerobias.org/:_authToken=${ZB_TOKEN}
```

### Step 12: Create Schema Files

Schema packages define AuditgraphDB object types using YAML files in specific directories.

#### Fields (`fields/`)

Fields are atomic properties with type definitions.

**Naming:** `{className}.{fieldName}.yml` (camelCase)

```yaml
# fields/agentSkill.license.yml
description: 'License name or SPDX identifier'
displayName: 'License'
type: string
```

**Supported field types:** `string`, `boolean`, `number`, `integer`, `date`, `datetime`

#### Interfaces (`interfaces/`)

Interfaces define shared property contracts that classes can extend.

**Naming:** `{InterfaceName}.yml` (PascalCase)

```yaml
# interfaces/GitHubObject.yml
description: "Common properties for GitHub resources"
properties:
  - nodeId:
    field: team.nodeId
```

#### Classes (`classes/`)

Classes define AuditgraphDB object types. They can extend base classes and interfaces.

**Naming:** `{ClassName}.yml` (PascalCase)

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
  - homepage:
    field: repository.homepage
viewProperties:
  "Name":
    jsonata: name
    sort: name
  "Description":
    jsonata: description
    sort: description
```

**Class structure:**
- `description` (required): What this class represents
- `extends` (optional): Parent classes/interfaces to inherit from
  - `Element`: Base AuditgraphDB type with `id`, `name`, `description`, `code`, `externalId`, tags, links
  - Custom interfaces defined in this package
- `properties` (optional): Properties mapping to fields
  - Simple field: `- propName:\n    field: className.fieldName`
  - Link to other class: `- propName:\n    linkTo: OtherClass\n    multi: true`
- `viewProperties` (optional): Default UI display columns
  - `jsonata`: JSONata expression to extract value
  - `sort`: Field to sort by

**Common base classes to extend:**
- `Element` - Base class with framework linking capability (demonstrates, child_of, etc.)
- `Repository` - Source code repositories
- `SourceCodeMgmtAcct` - Source code management accounts
- `FederatedIdentity` - Federated identity objects
- Custom interfaces from the same or imported schema packages

#### Documents (`documents/`) — Optional

Documents define complex nested object structures.

```yaml
# documents/organization.plan.yml
description: 'GitHub Organization Plan information'
displayName: Plan
properties:
  - name:
    field: object.name
  - seats:
    field: organization.plan.seats
```

#### Enums (`enums/`) — Optional

Enums define enumerated value sets.

```yaml
# enums/organization.defaultRepositoryPermission.yml
description: The default repository permission for organization members.
displayName: Default Repository Permission
values:
  - read: 'Members can only read repositories.'
  - write: 'Members can read and write to repositories.'
  - admin: 'Members have full admin access to repositories.'
  - none: 'Members have no default repository permissions.'
```

### Step 13: Install and Validate

```bash
cd package/{vendorCode}/{schemaCode}
npm install
npm run validate
```

**If product dependency is not yet published, use npm link:**

```bash
# In product repo
cd /path/to/product/package/{vendorCode}/{schemaCode}
npm link

# In schema repo
cd /path/to/schema/package/{vendorCode}/{schemaCode}
npm link @zerobias-org/product-{vendorCode}-{schemaCode}
npm install
```

### Step 14: Commit and Push

```bash
git add package/{vendorCode}/{schemaCode}/
git commit -m "feat({vendorCode}-{schemaCode}): add {Schema Name} schema

- Add {N} classes, {N} interfaces, {N} fields
- Extends Element for framework linking

Task: ${task.code}
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"

git push origin feat/schema-{vendorCode}-{schemaCode}
```

### Step 15: Create Pull Request

```bash
gh pr create --title "feat({vendorCode}-{schemaCode}): add {Schema Name} schema" --body "$(cat <<'EOF'
## Summary
- **Task:** {task.code}
- **Vendor:** {vendorCode}
- **Schema:** {schemaCode}
- **Package:** @zerobias-org/schema-{vendorCode}-{schemaCode}

## Schema Contents
- **Classes:** {count} ({list class names})
- **Interfaces:** {count}
- **Fields:** {count}

## Dependencies
- Product: @zerobias-org/product-{vendorCode}-{schemaCode}
- Platform Schema: @auditmation/schema-auditmation-auditmation-platform

## Validation
- [x] `npm run validate` passes
- [x] catalog.yml has all required fields
- [x] All classes have descriptions
- [x] All fields have types

## Task Reference
- **Task Code:** {task.code}
- **Task ID:** {task.id}

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Step 16: Update Task Status

```javascript
// Add completion comment
zerobias_execute("platform.Task.addComment", {
  id: task.id,
  newTaskComment: {
    commentMarkdown: `## Schema Created

**Task:** ${task.code}
**Package:** @zerobias-org/schema-${vendorCode}-${schemaCode}
**Branch:** feat/schema-${vendorCode}-${schemaCode}
**PR:** ${prUrl}

### Schema Contents
- Classes: ${classCount}
- Interfaces: ${interfaceCount}
- Fields: ${fieldCount}

### Dependencies
- Product: @zerobias-org/product-${vendorCode}-${schemaCode}
- Platform Schema: @auditmation/schema-auditmation-auditmation-platform

### Next Steps
- PR needs review and merge
- After merge, schema will be loaded by dataloader
- Collector bot can then be created to populate data`
  }
})

// Transition to awaiting_approval
zerobias_execute("platform.Task.update", {
  id: task.id,
  updateTask: {
    transitionId: "f017a447-0994-594d-9417-39cbc9a4de88"  // Peer Review
  }
})
```

---

## Linking Tasks

Link schema task to related tasks (vendor, product, collector bot):

```javascript
const relatesToLinkType = "b8bd95d0-b33c-11f0-8af3-dfaccf31600e"

// Link to product task (dependency)
zerobias_execute("platform.Resource.linkResources", {
  fromResource: schemaTaskId,
  toResource: productTaskId,
  linkType: relatesToLinkType
})

// Link to collector bot task (downstream)
zerobias_execute("platform.Resource.linkResources", {
  fromResource: schemaTaskId,
  toResource: collectorBotTaskId,
  linkType: relatesToLinkType
})
```

**Note:** Use `toResource` (not `toResourceId`), and `linkType` must be a UUID.

---

## Dependency Resolution

When a required dependency doesn't exist:

### 1. Create Subtask

```javascript
zerobias_execute("platform.Task.create", {
  newTask: {
    name: `Create ${depType}: ${depName}`,
    description: `Required dependency for ${task.code}: ${task.name}

Parent Task: ${task.code}
Parent Task ID: ${task.id}`,
    status: "todo",
    customFields: {
      artifactType: depType,
      vendor: vendorCode,
      repoUrl: depRepoUrl,
      branchName: `feat/${depType}-${depName}`,
      parentTaskId: task.id,
      parentTaskCode: task.code
    }
  }
})
```

### 2. Block Parent Task

```javascript
zerobias_execute("platform.Task.addComment", {
  id: task.id,
  newTaskComment: {
    commentMarkdown: `**Status: Blocked**

Missing dependency: ${depType} '${depName}'
Subtask created: ${subtask.code}

Will resume when dependency is completed.`
  }
})
```

### 3. Process Dependency

Run the appropriate skill for the dependency:
- Missing vendor: `/create-vendor {vendor-task-id}`
- Missing product: Create product package manually (in `org/product/` repo)

### 4. Resume Schema Creation

After dependencies are complete, resume from Step 7.

---

## Common Issues

### Validation fails: "package.json name must match @zerobias-org/schema-*"
- Ensure package name follows format: `@zerobias-org/schema-{vendorCode}-{schemaCode}`

### Validation fails: "catalog.yml Schema.package needs replacement"
- Replace `{vendor}.{code}.schema` placeholder with actual values

### Validation fails: "missing zerobias (or auditmation) section"
- Ensure `zerobias` section exists in package.json with `import-artifact: "schema"`

### Validation fails: "must contain at least one of: classes/, interfaces/, or fields/"
- At minimum one of these directories must exist and contain YAML files

### Product dependency not found during npm install
If the product package is not yet published:
1. Use `npm link` as described in Step 13
2. Or wait for product PR to be merged and published

### Platform schema import errors
- Ensure `@auditmation/schema-auditmation-auditmation-platform` is in dependencies
- This provides base classes like `Element`, `Repository`, etc.

---

## Schema Design Guidelines

### Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Class | PascalCase | `GitHubRepository` |
| Interface | PascalCase | `GitHubObject` |
| Field file | camelCase dot-notation | `repository.fullName.yml` |
| Document file | camelCase dot-notation | `organization.plan.yml` |
| Enum file | camelCase dot-notation | `team.privacy.yml` |

### Extending Element for Framework Linking

When a class extends `Element`, it inherits:
- `id`, `name`, `description`, `code`, `externalId`
- Tags and resource linking
- Framework linking capability (demonstrates, child_of, demonstrated_by)

**Use `Element` when:** The class represents a discoverable asset that may need compliance mapping.

### Property Types

| Pattern | Usage |
|---------|-------|
| `field: className.fieldName` | Reference to a field definition |
| `linkTo: OtherClass` | Link to another class |
| `linkTo: OtherClass` + `multi: true` | One-to-many link |
| `linkTo: OtherClass` + `multi: true` + `t3: permissionSet` | Link with tertiary metadata |

---

## Workflow Transitions Reference

| Transition | Target Status | ID |
|------------|---------------|-----|
| Start | in_progress | `7f140bbe-4c10-54ac-922c-460c66392fad` |
| Peer Review | awaiting_approval | `f017a447-0994-594d-9417-39cbc9a4de88` |
| Accept | released | `1d2e9381-f609-5e26-8bc6-7bbb65a9048d` |
| Reject | in_progress | `dda277e6-12d4-581b-922c-4e80d58d9083` |
| Cancel | cancelled | `711aa97f-f0bf-5c56-936f-f5e54d9de1f3` |

**Note:** Always get actual IDs from `task.nextTransitions`.

---

## Dependency Chains

```
Standards workflow:  vendor → [suite] → [product] → framework/standard/benchmark → crosswalk
Data workflow:       vendor → [suite] → [product] → schema → collectorbot → pipeline
```

- **Vendor** is always the root — required
- **Suite** and **Product** are optional in both chains
- **Collector bots REQUIRE schemas** - schema must exist before collector bot
- Schemas define the AuditgraphDB object types that collector bots populate
- Suite is NOT required for schemas (it's optional on the data path)

---

## References

- **Meta-repo CLAUDE.md:** `../../CLAUDE.md`
- **Orchestration docs:** `../../docs/orchestration/`
- **Product repo:** `../../product/`
- **Collector bot repo:** `../../collectorbot/`
- **Templates:** `templates/`
- **Existing schema examples:** `auditlogic/schema/package/` (e.g., `github/github/`)
