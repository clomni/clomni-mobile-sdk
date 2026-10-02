package ai.clomni.reactnative

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

/** Autolinking finds this; the old architecture makes [ClomniModule] with the bridge. */
class ClomniPackage : ReactPackage {
    // Deprecated in React Native 0.86, which has no old architecture; this file serves 0.72 – 0.81.
    @Suppress("OVERRIDE_DEPRECATION")
    override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> =
        listOf(ClomniModule(reactContext))

    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> = emptyList()
}
