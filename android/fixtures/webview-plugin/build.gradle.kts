// Not shipped: a stand-in for a library that declares androidx's FileProvider itself, as unity-webview's
// WebViewPlugin.aar does (CM-185), for the provider-collision fixture's flavor "library". Only its manifest and paths
// matter; it has no code.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "ai.clomni.fixtures.webview"
    compileSdk = 36

    defaultConfig {
        minSdk = 23
    }
}
