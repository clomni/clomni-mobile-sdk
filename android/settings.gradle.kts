pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "clomni-messenger"

include(":messenger", ":sample")
// Build fixtures, never published: apps that build the SDK the way a customer's app does (fixtures/*/build.gradle.kts).
include(":fixtures:webview-plugin", ":fixtures:provider-collision")
