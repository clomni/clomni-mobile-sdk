package ai.clomni.flutter

import ai.clomni.messenger.Clomni
import ai.clomni.messenger.ClomniLogLevel
import ai.clomni.messenger.ClomniPush
import ai.clomni.messenger.ClomniThemeMode
import ai.clomni.messenger.ClomniUser
import ai.clomni.messenger.ConversationStartedListener
import ai.clomni.messenger.FlowCompletedListener
import ai.clomni.messenger.MessengerClosedListener
import ai.clomni.messenger.MessengerOpenedListener
import ai.clomni.messenger.UnreadCountListener
import android.content.Context
import android.graphics.Typeface
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/**
 * The Android side of clomni_flutter: the method channel's calls go to the Android SDK's [Clomni] facade, and the
 * SDK's events go to the event channel as `{name, count?, text?}` maps, while Dart listens.
 */
class ClomniFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null

    @Volatile
    private var unreadCount = 0

    private val unreadListener = UnreadCountListener { count ->
        unreadCount = count
        send("unreadCountChanged", count = count)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "ai.clomni.flutter/methods").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "ai.clomni.flutter/events").also { it.setStreamHandler(this) }
        // The app's Dart hears these; native code of the app should not set them as well.
        Clomni.onMessengerOpened(MessengerOpenedListener { source -> send("messengerOpened", text = source) })
        Clomni.onMessengerClosed(MessengerClosedListener { send("messengerClosed") })
        Clomni.onConversationStarted(ConversationStartedListener { id -> send("conversationStarted", text = id) })
        Clomni.onFlowCompleted(FlowCompletedListener { flowId -> send("flowCompleted", text = flowId) })
        Clomni.addUnreadCountListener(unreadListener)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        Clomni.removeUnreadCountListener(unreadListener)
        Clomni.onMessengerOpened(null)
        Clomni.onMessengerClosed(null)
        Clomni.onConversationStarted(null)
        Clomni.onFlowCompleted(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /** The SDK calls back on the main thread, where an EventSink must be used. */
    private fun send(name: String, count: Int? = null, text: String? = null) {
        val event = HashMap<String, Any>()
        event["name"] = name
        if (count != null) event["count"] = count
        if (text != null) event["text"] = text
        sink?.success(event)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val answer = handle(call) ?: return result.notImplemented()
            result.success(if (answer == Unit) null else answer)
        } catch (e: RuntimeException) {
            result.error("bad_arguments", "${call.method}: ${e.message}", null)
        }
    }

    /** What the call answers (Unit for nothing), or null for a call this plugin does not know. */
    private fun handle(call: MethodCall): Any? {
        when (call.method) {
            "setup" -> Clomni.initialize(context, call.argument<String>("appId")!!, call.argument<String>("apiKey")!!,
                call.argument<String>("region") ?: "eu")
            "loginUser" -> {
                val user = call.argument<Map<String, String>>("user") ?: emptyMap()
                Clomni.loginUser(ClomniUser(user["userId"], user["email"], user["phone"], user["name"]),
                    call.argument<String>("userHash"))
            }
            "loginUnidentifiedUser" -> Clomni.loginUnidentifiedUser()
            "updateUser" -> Clomni.updateUser(call.argument<String>("name"), call.argument<String>("language"),
                call.argument<Map<String, Any?>>("customAttributes"))
            "logout" -> Clomni.logout()
            "setLogLevel" -> setLogLevel(call.arguments as String)
            "setTypeface" -> Clomni.setTypeface((call.arguments as String?)?.let(::typeface))
            // The SDK checks the colour; the mode is one of Dart's enum's names.
            "setTheme" -> Clomni.setTheme(call.argument<String>("primaryColor"),
                call.argument<String>("typeface")?.let(::typeface),
                call.argument<String>("mode")?.let { ClomniThemeMode.valueOf(it.uppercase()) })
            "present" -> Clomni.present(call.arguments as String?)
            "presentNewConversation" -> Clomni.presentNewConversation(call.arguments as String?)
            "presentConversation" -> Clomni.presentConversation(call.arguments as String)
            "dismiss" -> Clomni.dismiss()
            "startFlow" -> Clomni.startFlow(call.argument<String>("event")!!,
                call.argument<Map<String, Any?>>("data") ?: emptyMap(), call.argument<Boolean>("openMessenger") ?: false,
                call.argument<String>("source"))
            "setLauncherVisible" -> Clomni.setLauncherVisible(call.arguments as Boolean)
            "setBottomPadding" -> Clomni.setBottomPadding((call.arguments as Number).toDouble().roundToInt())
            "setDeviceToken" -> Clomni.setDeviceToken(call.arguments as String)
            // An FCM data message: the SDK shows Clomni's as a notification, whose tap opens the conversation.
            "handlePush" -> {
                @Suppress("UNCHECKED_CAST")
                return ClomniPush.handle(context, call.arguments as Map<String, String>)
            }
            // Android shows or hides its own notifications; the Dart side does not ask here.
            "shouldShowForeground" -> return true
            "setNotificationIcon" -> setNotificationIcon(call.arguments as String)
            "getUnreadCount" -> return unreadCount
            else -> return null
        }
        return Unit
    }

    private fun setLogLevel(level: String) {
        val known = ClomniLogLevel.values().firstOrNull { it.name.equals(level, ignoreCase = true) }
        if (known == null) {
            Log.w(TAG, "setLogLevel: unknown level \"$level\"")
            return
        }
        Clomni.setLogLevel(known)
    }

    /** A font family as Android knows it: res/font/<name> (API 26+), else a family the system has. */
    private fun typeface(familyName: String): Typeface {
        val id = context.resources.getIdentifier(familyName.lowercase(), "font", context.packageName)
        if (id != 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) return context.resources.getFont(id)
        return Typeface.create(familyName, Typeface.NORMAL)
    }

    /** A drawable's name (res/drawable or res/mipmap), for Clomni's notifications. */
    private fun setNotificationIcon(name: String) {
        val resources = context.resources
        val id = resources.getIdentifier(name, "drawable", context.packageName).takeIf { it != 0 }
            ?: resources.getIdentifier(name, "mipmap", context.packageName)
        if (id == 0) {
            Log.w(TAG, "setNotificationIcon: no drawable \"$name\" in the app; the app's icon stays")
            return
        }
        Clomni.setNotificationIcon(id)
    }

    private companion object {
        const val TAG = "Clomni"
    }
}
