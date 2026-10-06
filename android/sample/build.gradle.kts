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
        // An App SDK inbox's keys (Clomni panel → Mobil tətbiq): -Pclomni.appId=… -Pclomni.apiKey=…
        buildConfigField("String", "CLOMNI_APP_ID", "\"${providers.gradleProperty("clomni.appId").getOrElse("app_demo")}\"")
        buildConfigField("String", "CLOMNI_API_KEY", "\"${providers.gradleProperty("clomni.apiKey").getOrElse("android_sdk-demo")}\"")
    }

    buildFeatures {
        buildConfig = true
        resValues = true
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

// Real pushes: put a Firebase project's google-services.json (package ai.clomni.messenger.sample) next to this file.
// It is read here the way the Google Services plugin would, without adding the plugin to the build; without it the
// sample builds as before and FCM stays off. The file is not committed.
val firebaseConfig = file("google-services.json")
if (firebaseConfig.exists()) {
    @Suppress("UNCHECKED_CAST")
    val json = groovy.json.JsonSlurper().parse(firebaseConfig) as Map<String, Any?>
    val project = json["project_info"] as Map<String, Any?>
    val client = (json["client"] as List<Map<String, Any?>>).first {
        ((it["client_info"] as Map<*, *>)["android_client_info"] as Map<*, *>)["package_name"] == "ai.clomni.messenger.sample"
    }
    val apiKey = ((client["api_key"] as List<Map<String, Any?>>).first())["current_key"] as String
    android.defaultConfig {
        resValue("string", "google_app_id", (client["client_info"] as Map<*, *>)["mobilesdk_app_id"] as String)
        resValue("string", "gcm_defaultSenderId", project["project_number"] as String)
        resValue("string", "google_api_key", apiKey)
        resValue("string", "project_id", project["project_id"] as String)
    }
}

dependencies {
    implementation(project(":messenger"))
    implementation(platform("com.google.firebase:firebase-bom:33.4.0"))
    implementation("com.google.firebase:firebase-messaging")
}
