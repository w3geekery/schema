---
name: create-schema
description: Create AuditgraphDB schema packages from ZeroBias tasks with automatic dependency resolution. Use when adding new object types, classes, interfaces, or fields to the graph database.
argument-hint: "[task-id]"
disable-model-invocation: true
---

Create AuditgraphDB schema packages from ZeroBias tasks with automatic dependency resolution and proper task management.

## Usage

```
/create-schema [task-id]
```

**Arguments:**
- `task-id` (optional): ZeroBias task UUID or task name. If not provided, will prompt for input.

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

**Task code is NOT searchable** — use UUID or task name.

### Step 2: Extract Schema Information

| Field | Source | Example |
|-------|--------|---------|
| **Vendor Code** | Parse from name | `github` |
| **Schema Code** | Parse from name | `github` |
| **Schema Name** | Parse from name | `GitHub Schema` |

Parse from task name format: `"Create schema: {vendor}/{code} ({name})"`

### Step 3: Assign and Transition to In Progress

```javascript
const party = zerobias_execute("platform.Party.getMyParty", {})
zerobias_execute("platform.Task.update", {
  id: task.id,
  updateTask: {
    assigned: party.id,
    customFields: {
      artifactType: "schema",
      repoUrl: "https://github.com/zerobias-org/schema",
      branchName: `feat/schema-${vendorCode}-${schemaCode}`
    },
    transitionId: "7f140bbe-4c10-54ac-922c-460c66392fad"
  }
})
```

### Step 4: Check Dependencies (MANDATORY)

```
Data workflow: vendor → [suite] → [product] → schema → collectorbot → pipeline
```

```javascript
// Check vendor exists
const vendors = zerobias_execute("portal.Vendor.search", {
  searchVendorBody: { search: vendorCode }
})

// Check product exists
const products = zerobias_execute("portal.Product.search", {
  searchProductBody: { search: `${vendorCode} ${schemaCode}` }
})
```

If dependencies are missing, create subtasks for the missing vendor/product before proceeding.

### Step 5: Create Git Branch

```bash
cd org/schema
git checkout main && git pull origin main
git checkout -b feat/schema-{vendorCode}-{schemaCode}
```

### Step 6: Create Package Files

See [templates.md](templates.md) for complete file templates.

**Directory structure:**
```
package/{vendorCode}/{schemaCode}/
├── package.json
├── catalog.yml
├── .npmrc
├── classes/
│   └── {ClassName}.yml
├── interfaces/      (optional)
├── fields/          (optional)
├── documents/       (optional)
└── enums/           (optional)
```

**Key conventions:**
- Package name: `@zerobias-org/schema-{vendorCode}-{schemaCode}`
- `{vendorCode}` and `{schemaCode}` must match `^[a-z0-9]+$` — **lowercase alphanumeric only, no hyphens/underscores/dots** (matches ZB platform `vspCodeValidator`)
- `{schemaCode}` must be identical across npm package, catalog, directory, and product dependency
- Enum values **MUST be ALL_CAPS** (`[A-Z][A-Z0-9_]*`) — dataloader rejects lowercase
- Config key: `zerobias` (not `auditmation`)
- Dataloader version: `"1.0.0"`
- Platform schema dep: `@zerobias-com/schema-zerobias-zerobias-platform`
- Base schema dep: `@zerobias-org/schema-zerobias-zerobias-base`
- Scripts use `tsx`
- Starting version: `"1.0.0-rc.1"`
- Must include `nx:prepublish` script
- **NEVER rename** a published schema package without platform team coordination (see repo CLAUDE.md)

### Step 7: Install and Validate

```bash
cd package/{vendorCode}/{schemaCode}
npm install
npm run validate
```

If product dependency is not yet published, use `file:` path or `npm link`.

### Step 8: Commit, Push, and Create PR

```bash
git add package/{vendorCode}/{schemaCode}/
git commit -m "feat({vendorCode}-{schemaCode}): add {Schema Name} schema

- Add {N} classes
- Extends Element for framework linking

Task: ${task.code}"

git push origin feat/schema-{vendorCode}-{schemaCode}

gh pr create --title "feat({vendorCode}-{schemaCode}): add {Schema Name} schema" --body "$(cat <<'EOF'
## Summary
- **Package:** @zerobias-org/schema-{vendorCode}-{schemaCode}
- **Classes:** {list}

## Validation
- [x] `npm run validate` passes
- [x] All classes have descriptions

## Task Reference
- **Task:** {task.code}

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Step 9: Update Task Status

```javascript
// Transition to awaiting_approval
zerobias_execute("platform.Task.update", {
  id: task.id,
  updateTask: {
    transitionId: "f017a447-0994-594d-9417-39cbc9a4de88"
  }
})
```

## Workflow Transitions

| Transition | Target Status | ID |
|------------|---------------|-----|
| Start | in_progress | `7f140bbe-4c10-54ac-922c-460c66392fad` |
| Peer Review | awaiting_approval | `f017a447-0994-594d-9417-39cbc9a4de88` |
| Accept | released | `1d2e9381-f609-5e26-8bc6-7bbb65a9048d` |

**Note:** Always get actual IDs from `task.nextTransitions`.
