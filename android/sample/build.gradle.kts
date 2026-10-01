import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "ai.clomni.messenger.sample"
    compileSdk = 36

    defaultConfig {
        applicationId = "ai.clomni.messenger.sample"
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        // An App SDK inbox's keys (Clomni panel → Mobil tətbiq): -Pclomni.appId=… -Pclomni.apiKey=… [-Pclomni.baseUrl=…]
        buildConfigField("String", "CLOMNI_APP_ID", "\"${providers.gradleProperty("clomni.appId").getOrElse("app_demo")}\"")
        buildConfigField("String", "CLOMNI_API_KEY", "\"${providers.gradleProperty("clomni.apiKey").getOrElse("android_sdk-demo")}\"")
        buildConfigField("String", "CLOMNI_BASE_URL", "\"${providers.gradleProperty("clomni.baseUrl").getOrElse("")}\"")
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":messenger"))
}
