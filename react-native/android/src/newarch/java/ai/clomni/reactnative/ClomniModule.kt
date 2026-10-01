package ai.clomni.reactnative

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap

/** The New Architecture's TurboModule: the spec codegen writes from src/NativeClomni.ts, done by [ClomniModuleImpl]. */
class ClomniModule(context: ReactApplicationContext) : NativeClomniSpec(context) {
    // The emitter is wired up by React Native after the module is made; an event before that has no one to reach.
    private val impl = ClomniModuleImpl(context) { if (mEventEmitterCallback != null) emitOnEvent(it) }

    override fun invalidate() {
        impl.invalidate()
        super.invalidate()
    }

    override fun setup(appId: String, apiKey: String, region: String) = impl.setup(appId, apiKey, region)

    override fun loginUser(user: ReadableMap, userHash: String?) = impl.loginUser(user, userHash)

    override fun loginUnidentifiedUser() = impl.loginUnidentifiedUser()

    override fun updateUser(name: String?, language: String?, customAttributes: ReadableMap?) = impl.updateUser()

    override fun logout() = impl.logout()

    override fun setLogLevel(level: String) = impl.setLogLevel()

    override fun setTypeface(familyName: String?) = impl.setTypeface()

    override fun present(source: String?) = impl.present(source)

    override fun presentNewConversation(source: String?) = impl.presentNewConversation(source)

    override fun presentConversation(conversationId: String) = impl.presentConversation(conversationId)

    override fun dismiss() = impl.dismiss()

    override fun startFlow(event: String, data: ReadableMap, openMessenger: Boolean, source: String?) =
        impl.startFlow(event, data, openMessenger, source)

    override fun setLauncherVisible(visible: Boolean) = impl.setLauncherVisible(visible)

    override fun setBottomPadding(padding: Double) = impl.setBottomPadding(padding)

    override fun setDeviceToken(token: String) = impl.setDeviceToken()

    override fun handlePush(data: ReadableMap) = impl.handlePush(data)

    override fun shouldShowForeground(data: ReadableMap): Boolean = impl.shouldShowForeground()

    override fun setNotificationIcon(name: String) = impl.setNotificationIcon()

    override fun getUnreadCount(promise: Promise) = impl.getUnreadCount(promise)

    // Events go through the spec's onEvent emitter; NativeEventEmitter's bookkeeping is not needed here.
    override fun addListener(eventName: String) = Unit

    override fun removeListeners(count: Double) = Unit
}
