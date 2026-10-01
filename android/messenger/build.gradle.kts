import kotlinx.kover.gradle.plugin.dsl.CoverageUnit
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kover)
}

group = "ai.clomni"
version = "1.0.0-SNAPSHOT"

// The JSON Schemas and fixtures shared with the server and the iOS SDK (repo root, not under android/).
val protocolDir: File = rootProject.file("../protocol")

android {
    namespace = "ai.clomni.messenger"
    compileSdk = 36

    defaultConfig {
        minSdk = 23
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.all { test ->
            test.systemProperty("clomni.protocol.dir", protocolDir.absolutePath)
            test.inputs.dir(protocolDir).withPropertyName("protocol").withPathSensitivity(PathSensitivity.RELATIVE)
        }
    }
}

kotlin {
    explicitApi()
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
}

kover {
    reports {
        filters {
            includes {
                packages("ai.clomni.messenger.protocol")
            }
        }
        variant("debug") {
            // Brief 11: protocol test coverage of at least 80%.
            verify {
                rule("Protocol line coverage") {
                    minBound(80, CoverageUnit.LINE)
                }
                rule("Protocol branch coverage") {
                    minBound(80, CoverageUnit.BRANCH)
                }
            }
        }
    }
}
