package ai.clomni.reactnative

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.modules.core.DeviceEventManagerModule

/** The old architecture's module (React Native 0.72 – 0.81 without the New Architecture), done by [ClomniModuleImpl]. */
class ClomniModule(context: ReactApplicationContext) : ReactContextBaseJavaModule(context) {
    private val impl = ClomniModuleImpl(context) { event ->
        if (context.hasActiveReactInstance()) {
            context.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                .emit(ClomniModuleImpl.NAME_EVENT, event)
        }
    }

    override fun getName(): String = ClomniModuleImpl.NAME

    override fun invalidate() {
        impl.invalidate()
        super.invalidate()
    }

    @ReactMethod
    fun setup(appId: String, apiKey: String, region: String) = impl.setup(appId, apiKey, region)

    @ReactMethod
    fun loginUser(user: ReadableMap, userHash: String?) = impl.loginUser(user, userHash)

    @ReactMethod
    fun loginUnidentifiedUser() = impl.loginUnidentifiedUser()

    @ReactMethod
    fun updateUser(name: String?, language: String?, customAttributes: ReadableMap?) =
        impl.updateUser(name, language, customAttributes)

    @ReactMethod
    fun logout() = impl.logout()

    @ReactMethod
    fun setLogLevel(level: String) = impl.setLogLevel(level)

    @ReactMethod
    fun setTypeface(familyName: String?) = impl.setTypeface(familyName)

    @ReactMethod
    fun setTheme(primaryColor: String?, typeface: String?, mode: String?) = impl.setTheme(primaryColor, typeface, mode)

    @ReactMethod
    fun setSoundsEnabled(enabled: Boolean) = impl.setSoundsEnabled(enabled)

    @ReactMethod
    fun setLanguage(language: String?) = impl.setLanguage(language)

    @ReactMethod
    fun setLinkListener(enabled: Boolean) = impl.setLinkListener(enabled)

    @ReactMethod
    fun present(source: String?) = impl.present(source)

    @ReactMethod
    fun presentNewConversation(source: String?) = impl.presentNewConversation(source)

    @ReactMethod
    fun presentConversation(conversationId: String) = impl.presentConversation(conversationId)

    @ReactMethod
    fun dismiss() = impl.dismiss()

    @ReactMethod
    fun startFlow(event: String, data: ReadableMap, openMessenger: Boolean, source: String?) =
        impl.startFlow(event, data, openMessenger, source)

    @ReactMethod
    fun setLauncherVisible(visible: Boolean) = impl.setLauncherVisible(visible)

    @ReactMethod
    fun setBottomPadding(padding: Double) = impl.setBottomPadding(padding)

    @ReactMethod
    fun setDeviceToken(token: String) = impl.setDeviceToken(token)

    @ReactMethod
    fun handlePush(data: ReadableMap) = impl.handlePush(data)

    @ReactMethod(isBlockingSynchronousMethod = true)
    fun shouldShowForeground(data: ReadableMap): Boolean = impl.shouldShowForeground()

    @ReactMethod
    fun setNotificationIcon(name: String) = impl.setNotificationIcon(name)

    @ReactMethod
    fun getUnreadCount(promise: Promise) = impl.getUnreadCount(promise)

    // NativeEventEmitter calls these; the events are sent whether or not anyone listens.
    @ReactMethod
    fun addListener(eventName: String) = Unit

    @ReactMethod
    fun removeListeners(count: Double) = Unit
}
