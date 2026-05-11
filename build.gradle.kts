import com.zerobias.buildtools.content.SchemaPrimitives

plugins {
    id("zb.workspace")
}

group = "com.zerobias.schema"

// ════════════════════════════════════════════════════════════
// Schema content validator — owned by this repo.
//
// Philosophy (per Chris/Kevin): the dataloader is the source of truth
// for schema rules (UUID format, field types, class extends chain,
// link bidirectionality, etc.). Re-validating those here just creates
// drift risk — when the dataloader tightens a rule, the gate gets
// stale.
//
// This validator only enforces things the dataloader CANNOT or DOES
// NOT check:
//
//   1. Filesystem ↔ npm ↔ zerobias-block triangulation. Dataloader
//      reads zerobias.package but not the npm `name` field, and has
//      no view of the on-disk directory layout. A wrong npm name
//      publishes under the wrong package and only surfaces in prod.
//
//   2. At least one schema-definition directory has content. An
//      empty schema package would publish cleanly but contribute
//      nothing to the loaded AuditgraphDB.
//
//   3. Repo-wide unique `zerobias.package` values (separate
//      :validateUniquePackageNames task below). Dataloader sees one
//      artifact at a time; collisions only surface when the second
//      tries to overwrite the first.
//
// Everything else — class/interface/field syntax, link resolution,
// enum format, deprecation handling — is delegated to the dataloader
// running in testIntegrationDataloader during gate, which loads the
// artifact into an ephemeral Neon Postgres branch.
// ════════════════════════════════════════════════════════════
extra["contentValidator"] = { proj: org.gradle.api.Project ->
    val projectDir = proj.projectDir
    val tag = "[schema-validator] ${proj.path}"

    require(projectDir.resolve("catalog.yml").isFile)  { "$tag catalog.yml missing in ${projectDir.path}" }
    require(projectDir.resolve("package.json").isFile) { "$tag package.json missing in ${projectDir.path}" }
    require(projectDir.resolve(".npmrc").isFile)       { "$tag .npmrc missing in ${projectDir.path}" }

    val pkgDoc = SchemaPrimitives.parseJson(projectDir.resolve("package.json"))
    val zerobiasBlock = pkgDoc["zerobias"] as? Map<*, *>
    val auditmationBlock = pkgDoc["auditmation"] as? Map<*, *>
    val deprecated =
        (zerobiasBlock?.get("deprecated") ?: auditmationBlock?.get("deprecated")) == true

    // ── 1. At least one definition dir has content (skipped for deprecated) ──
    //
    // Deprecated schemas are placeholders that exist only to mark the
    // old npm name as renamed-or-dead in the dataloader. They legitimately
    // ship just catalog.yml + package.json with `zerobias.deprecated:
    // true`. zb.schema also skips TS gen + TS twin publish for them.
    if (!deprecated) {
        val defDirs = listOf("classes", "interfaces", "fields", "enums", "documents")
        val populated = defDirs.any { name ->
            projectDir.resolve(name).takeIf { it.isDirectory }
                ?.listFiles()
                ?.any { it.isFile && (it.extension == "yml" || it.extension == "yaml" || it.extension == "json") }
                ?: false
        }
        require(populated) {
            "$tag must contain at least one of $defDirs with at least one definition file (.yml/.yaml/.json)"
        }
    } else {
        proj.logger.lifecycle("$tag deprecated — skipping definition-dir check")
    }

    // ── 2. Filesystem ↔ npm ↔ zerobias-block triangulation ──
    //
    // Mixed-depth layout — both supported:
    //   package/{vendor}/{product}/        (depth 2)
    //   package/{vendor}/{group}/{product}/ (depth 3)
    //
    // npm name:        @zerobias-org/schema-<parts joined with '-'>
    // zerobias.package: <parts joined with '.'>.schema
    val packageRoot = proj.rootProject.projectDir.resolve("package")
    val parts = projectDir.relativeTo(packageRoot).path.split(java.io.File.separator)
    require(parts.size in 2..3) {
        "$tag unexpected directory depth ${parts.size} (parts=$parts). Expected 2 or 3 segments under package/."
    }
    SchemaPrimitives.requirePackageIdentity(
        pkgDoc,
        expectedNpmName = "@zerobias-org/schema-${parts.joinToString("-")}",
        expectedZerobiasPackage = "${parts.joinToString(".")}.schema",
        field = "$tag package.json",
    )

    // ── 3. Warn (don't fail) on legacy auditmation config key ──
    // zb.content's SchemaPrimitives reads either key; the warning helps
    // a future sweep drop the legacy fallback entirely.
    if (zerobiasBlock == null && auditmationBlock != null) {
        proj.logger.warn("$tag uses legacy 'auditmation' config key — recommend migrating to 'zerobias'")
    }

    proj.logger.lifecycle("$tag: parts=${parts.joinToString("/")}${if (deprecated) " (deprecated)" else ""}")
}

// ════════════════════════════════════════════════════════════
// :validateUniquePackageNames — repo-wide cross-cut.
//
// Schemas don't carry a top-level `id` UUID like vendor/suite. Their
// identity is `zerobias.package` — the canonical AuditgraphDB block
// identifier loaded by dataloader. Two artifacts with the same value
// would silently overwrite each other; dataloader can't see this
// because it processes one at a time.
//
// Wired as a dependency of every per-package validateContent so any
// gate run picks it up (gradle deduplicates).
// ════════════════════════════════════════════════════════════
val validateUniquePackageNames by tasks.registering {
    group = "verification"
    description = "Fail if two schema packages share the same zerobias.package value"

    val packageDir = layout.projectDirectory.dir("package").asFile
    inputs.files(
        fileTree(packageDir) {
            include("**/package.json")
            exclude("**/node_modules/**")
            exclude("**/ts/**")
        }
    )

    doLast {
        val byPkg = mutableMapOf<String, MutableList<String>>()
        packageDir.walkTopDown()
            .onEnter { it.name != "node_modules" && it.name != "ts" }
            .filter { it.isFile && it.name == "package.json" }
            .forEach { f ->
                val doc = try {
                    SchemaPrimitives.parseJson(f)
                } catch (e: Exception) {
                    logger.warn("[validateUniquePackageNames] skipping unparseable ${f.relativeTo(rootDir)}: ${e.message}")
                    return@forEach
                }
                val zb = doc["zerobias"] as? Map<*, *>
                val am = doc["auditmation"] as? Map<*, *>
                val pkgName = (zb?.get("package") ?: am?.get("package")) as? String ?: return@forEach
                byPkg.getOrPut(pkgName) { mutableListOf() }.add(f.relativeTo(rootDir).path)
            }

        val collisions = byPkg.filterValues { it.size > 1 }
        if (collisions.isNotEmpty()) {
            val report = collisions.entries.joinToString("\n") { (name, paths) ->
                "  $name\n    " + paths.joinToString("\n    ")
            }
            throw GradleException(
                "[validateUniquePackageNames] duplicate zerobias.package across the repo:\n$report"
            )
        }
        logger.lifecycle("[validateUniquePackageNames] ${byPkg.size} unique package names across ${byPkg.values.sumOf { it.size }} schemas")
    }
}

subprojects {
    tasks.matching { it.name == "validateContent" }.configureEach {
        dependsOn(rootProject.tasks.named("validateUniquePackageNames"))
    }
}

// ════════════════════════════════════════════════════════════
// :updateBundle — runs AFTER all per-package publishes succeed.
//
// The published reusable workflow (zbb-publish-reusable.yml) does NOT
// touch bundle/package.json today. We rebuild the dependencies map
// here from the on-disk version of every schema package, then commit
// + push the resulting bundle/package.json change. The publish
// workflow invokes this as a follow-up step after the publish matrix.
//
// Idempotent: re-running with no version changes produces no diff.
// ════════════════════════════════════════════════════════════
val updateBundle by tasks.registering {
    group = "publish"
    description = "Refresh bundle/package.json dependencies from the on-disk schema package versions"

    val bundleJson = rootProject.file("bundle/package.json")
    val packageDir = rootProject.file("package")

    doLast {
        require(bundleJson.isFile) { "[updateBundle] bundle/package.json missing" }
        require(packageDir.isDirectory) { "[updateBundle] package/ missing" }

        val mapper = com.fasterxml.jackson.databind.ObjectMapper()
            .enable(com.fasterxml.jackson.databind.SerializationFeature.INDENT_OUTPUT)

        // Build the dependencies map from every package.json on disk.
        val deps = sortedMapOf<String, String>()
        packageDir.walkTopDown()
            .onEnter { it.name != "node_modules" && it.name != "ts" }
            .filter { it.isFile && it.name == "package.json" }
            .forEach { f ->
                val doc = SchemaPrimitives.parseJson(f)
                val name = doc["name"] as? String ?: return@forEach
                val version = doc["version"] as? String ?: return@forEach
                deps[name] = version
            }

        // Update the bundle's dependencies in place — preserve all other
        // top-level fields (auditmation/zerobias block, repository, files,
        // etc.) so reviewers see only the diff that matters.
        val root = mapper.readTree(bundleJson) as com.fasterxml.jackson.databind.node.ObjectNode
        val depsNode = mapper.createObjectNode()
        deps.forEach { (k, v) -> depsNode.put(k, v) }
        root.set<com.fasterxml.jackson.databind.JsonNode>("dependencies", depsNode)

        bundleJson.writeText(mapper.writeValueAsString(root) + "\n")
        logger.lifecycle("[updateBundle] wrote ${deps.size} deps into ${bundleJson.relativeTo(rootDir)}")
    }
}

// ════════════════════════════════════════════════════════════
// :projectPaths — used by zbb CLI for project-to-directory mapping.
// :changedModules — used by debugging / migration tooling. Mixed-depth
//                   aware: looks at the actual project layout to decide
//                   how many path segments to keep.
// ════════════════════════════════════════════════════════════
val projectPaths by tasks.registering {
    group = "info"
    description = "Output project-to-directory mappings for tooling (used by zbb CLI)"
    doLast {
        subprojects.filter { it.buildFile.exists() }.forEach { p ->
            println("${p.path}=${p.projectDir.relativeTo(rootDir)}")
        }
    }
}

val changedModules by tasks.registering {
    group = "info"
    description = "List schemas changed since last version tag (mixed-depth aware)"
    doLast {
        val lastTag = try {
            providers.exec { commandLine("git", "describe", "--tags", "--abbrev=0") }
                .standardOutput.asText.get().trim()
        } catch (e: Exception) {
            logger.warn("No version tags found -- listing all schemas as changed")
            null
        }

        val diffArgs = if (lastTag != null) {
            listOf("git", "diff", "--name-only", lastTag, "HEAD")
        } else {
            listOf("git", "ls-files")
        }

        val result = providers.exec { commandLine(diffArgs) }.standardOutput.asText.get()

        // Build a set of valid package roots from the on-disk project
        // layout (relative to repo root, e.g. "package/hl7/fhir" or
        // "package/zerobias/zerobias/base"). Any changed file whose
        // prefix matches one of these belongs to that package.
        val packageRoots: List<String> = subprojects
            .filter { it.buildFile.exists() }
            .map { it.projectDir.relativeTo(rootDir).path }
            .sortedByDescending { it.length }   // match longest prefix first

        val changed = result.lines()
            .filter { it.startsWith("package/") }
            .mapNotNull { line -> packageRoots.firstOrNull { line.startsWith("$it/") || line == it } }
            .distinct()

        changed.forEach { println(it.removePrefix("package/")) }
    }
}
