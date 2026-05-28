// settings.gradle.kts — schema monorepo
//
// Plugin resolution order: mavenLocal (for `publishToMavenLocal` dev builds
// of build-tools) → GitHub Packages Maven → gradle plugin portal → mavenCentral.
// Never via `includeBuild` of a sibling repo path: dev iteration goes through
// `./gradlew publishToMavenLocal` from build-tools so CI and local resolve
// the artifact the same way.

pluginManagement {
    repositories {
        mavenLocal()
        maven {
            url = uri("https://maven.pkg.github.com/zerobias-org/util")
            credentials {
                username = System.getenv("GITHUB_ACTOR") ?: "zerobias-org"
                password = System.getenv("READ_TOKEN") ?: System.getenv("NPM_TOKEN") ?: System.getenv("GITHUB_TOKEN") ?: ""
            }
        }
        gradlePluginPortal()
        mavenCentral()
    }
    plugins {
        id("zb.workspace") version "1.+"
        id("zb.base") version "1.+"
        id("zb.content") version "1.+"
        id("zb.schema") version "1.+"
    }
}

rootProject.name = "zerobias-org-schemas"

// Auto-discover all schemas under package/.
// Mixed depth — schemas live at either:
//   package/<vendor>/<product>/         (depth 2)
//   package/<vendor>/<group>/<product>/ (depth 3)
// The marker walk picks up build.gradle.kts at any depth. The
// per-package build.gradle.kts is a one-line marker:
//   plugins { id("zb.schema") }
// Project paths mirror filesystem:
//   package/hl7/fhir              → :hl7:fhir
//   package/zerobias/zerobias/base → :zerobias:zerobias:base
val packageDir = file("package")
if (packageDir.exists()) {
    packageDir.walkTopDown()
        .filter { it.name == "build.gradle.kts" }
        .forEach { buildFile ->
            val moduleDir = buildFile.parentFile
            val relativePath = moduleDir.relativeTo(packageDir).path
            val projectPath = relativePath.replace(File.separatorChar, ':')

            include(projectPath)
            project(":$projectPath").projectDir = moduleDir
        }
}
