import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Not shipped (CM-185): an app with the SDK and a second androidx FileProvider under another authority, declared by the
// app itself (flavor "app") or by a library (flavor "library", ../webview-plugin, as unity-webview does). The manifest
// merger knows a provider by its class name: with the SDK's provider on androidx's own class, the merge stops
// ("… collides with another value"). The unit tests check that both providers are in the app and both hand out files.
//   ./gradlew :fixtures:provider-collision:testAppDebugUnitTest :fixtures:provider-collision:testLibraryDebugUnitTest
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "ai.clomni.fixtures.collision"
    compileSdk = 36

    defaultConfig {
        applicationId = "ai.clomni.fixtures.collision"
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    // Who declares the other provider: the app itself, in its manifest, or a library it depends on.
    flavorDimensions += "declaredBy"
    productFlavors {
        create("app") {
            dimension = "declaredBy"
            buildConfigField("String", "OTHER_AUTHORITY", "\"ai.clomni.fixtures.collision.fileprovider\"")
            buildConfigField("String", "OTHER_DIR", "\"files\"")
        }
        create("library") {
            dimension = "declaredBy"
            buildConfigField("String", "OTHER_AUTHORITY", "\"ai.clomni.fixtures.collision.unitywebview.fileprovider\"")
            buildConfigField("String", "OTHER_DIR", "\"webview\"")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Robolectric reads the merged manifest and the resources.
    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":messenger"))
    "libraryImplementation"(project(":fixtures:webview-plugin"))

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    // androidx's FileProvider for the tests to call; the app has it at runtime through the SDK, which gets androidx.core
    // the same way.
    testImplementation(libs.androidx.activity)
}
