# Schema Package Templates

## .npmrc

```
@auditmation:registry=https://pkg.zerobias.org
@auditlogic:registry=https://pkg.zerobias.org
@zerobias-org:registry=https://pkg.zerobias.org
@zerobias-com:registry=https://pkg.zerobias.org
//pkg.zerobias.org/:always-auth=true
//pkg.zerobias.org/:_authToken=${ZB_TOKEN}
```

## package.json — Vendor Schema

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
    "nx:prepublish": "../../../scripts/prepublish.sh",
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
    "catalog.yml"
  ],
  "dependencies": {
    "@zerobias-com/schema-zerobias-zerobias-platform": "latest",
    "@zerobias-org/product-{vendorCode}-{schemaCode}": "latest",
    "@zerobias-org/schema-zerobias-zerobias-base": "latest"
  },
  "zerobias": {
    "dataloader-version": "1.0.0",
    "import-artifact": "schema",
    "package": "{vendorCode}.{schemaCode}.schema",
    "imports": [
      "zerobias.zerobias.platform.schema",
      "zerobias.zerobias.base.schema"
    ]
  }
}
```

## package.json — Suite Schema (4 levels deep)

```json
{
  "name": "@zerobias-org/schema-{vendorCode}-{suiteCode}-{schemaCode}",
  "version": "1.0.0-rc.1",
  "description": "Schema for {Schema Name}",
  "author": "team@zerobias.com",
  "license": "ISC",
  "type": "module",
  "repository": {
    "type": "git",
    "url": "git@github.com:zerobias-org/schema.git",
    "directory": "package/{vendorCode}/{suiteCode}/{schemaCode}/"
  },
  "scripts": {
    "nx:prepublish": "../../../../scripts/prepublish.sh",
    "correct:deps": "tsx ../../../../scripts/correctDeps.ts",
    "validate": "tsx ../../../../scripts/validate.ts"
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
    "catalog.yml"
  ],
  "dependencies": {
    "@zerobias-com/schema-zerobias-zerobias-platform": "latest",
    "@zerobias-org/product-{vendorCode}-{suiteCode}-{schemaCode}": "latest",
    "@zerobias-org/schema-zerobias-zerobias-base": "latest"
  },
  "zerobias": {
    "dataloader-version": "1.0.0",
    "import-artifact": "schema",
    "package": "{vendorCode}.{suiteCode}.{schemaCode}.schema",
    "imports": [
      "zerobias.zerobias.platform.schema",
      "zerobias.zerobias.base.schema"
    ]
  }
}
```

## catalog.yml

```yaml
Schema:
  name: "{Schema Name}"
  package: "{vendorCode}.{schemaCode}.schema"
  description: |-
    AuditgraphDB schema for {Schema Name}
```

- `Schema` top-level key is required
- `package` must match `zerobias.package` in package.json
- Replace all template placeholders
