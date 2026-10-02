import kotlinx.kover.gradle.plugin.dsl.CoverageUnit
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kover)
    alias(libs.plugins.paparazzi)
    alias(libs.plugins.binary.compatibility.validator)
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
        // Sent as X-Clomni-SDK: android/<version> on every request.
        buildConfigField("String", "SDK_VERSION", "\"$version\"")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    // Library resources merge into the app's: ours all start with clomni_.
    resourcePrefix = "clomni_"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.all { test ->
            test.systemProperty("clomni.protocol.dir", protocolDir.absolutePath)
            // DocsTest reads docs/integration.md and the sample it quotes.
            test.systemProperty("clomni.android.dir", rootProject.projectDir.absolutePath)
            test.inputs.dir(rootProject.file("docs")).withPropertyName("docs").withPathSensitivity(PathSensitivity.RELATIVE)
            test.inputs.dir(rootProject.file("sample/src/main")).withPropertyName("sample").withPathSensitivity(PathSensitivity.RELATIVE)
            test.inputs.dir(protocolDir).withPropertyName("protocol").withPathSensitivity(PathSensitivity.RELATIVE)
        }
    }
}

kotlin {
    explicitApi()
    // Readable by apps on Kotlin 1.8+ (see libs.versions.toml): Kotlin 1.9 metadata and a 1.9 stdlib dependency.
    coreLibrariesVersion = libs.versions.kotlinStdlib.get()
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
        languageVersion.set(KotlinVersion.KOTLIN_1_9)
        apiVersion.set(KotlinVersion.KOTLIN_1_9)
    }
}

dependencies {
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.coil.compose)
    implementation(libs.androidx.activity)

    testImplementation(libs.junit)
    testImplementation(libs.okhttp.mockwebserver)

    // On a device (CI's emulator): the Keystore, the activity lifecycle, initialize under StrictMode, accessibility.
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.compose.ui.test.junit4.accessibility)
    androidTestImplementation(libs.compose.ui.test.manifest)
}

kover {
    reports {
        filters {
            includes {
                packages("ai.clomni.messenger.protocol", "ai.clomni.messenger.store")
            }
        }
        variant("debug") {
            // Brief 11: Protocol and Store test coverage of at least 80%.
            verify {
                rule("Protocol and Store line coverage") {
                    minBound(80, CoverageUnit.LINE)
                }
                rule("Protocol and Store branch coverage") {
                    minBound(80, CoverageUnit.BRANCH)
                }
            }
        }
    }
}

// What apps can use is ai.clomni.messenger's facade (Clomni, ClomniPush and their parameter types); everything below it
// is internal. Two generated classes have no Kotlin visibility and are left out of the dump by name, so a new one
// shows up in review: AGP's BuildConfig (the SDK version) and the Compose compiler's lambda holder.
apiValidation {
    ignoredClasses += listOf(
        "ai.clomni.messenger.BuildConfig",
        "ai.clomni.messenger.ui.ComposableSingletons\$ClomniMessengerActivityKt",
    )
}

// Brief 11: the release AAR (a library: not shrunk here, R8 runs in the app) is at most 1.5 MB. Part of CI.
val checkAarSize by tasks.registering {
    description = "Fails when the release AAR is larger than 1.5 MB."
    group = "verification"
    val aar = layout.buildDirectory.file("outputs/aar/messenger-release.aar")
    dependsOn("bundleReleaseAar")
    inputs.file(aar)
    doLast {
        val bytes = aar.get().asFile.length()
        val limit = 1_500_000L
        logger.lifecycle("messenger-release.aar: $bytes bytes (limit $limit)")
        check(bytes <= limit) { "messenger-release.aar is $bytes bytes, over the brief's 1.5 MB" }
    }
}
