package ai.clomni.messenger.sample

import ai.clomni.messenger.Clomni
import ai.clomni.messenger.ClomniPush
import ai.clomni.messenger.UnreadCountListener
import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView

/**
 * The ways into the messenger of brief 8·7.2 on one plain screen (no Compose, no AppCompat): the app's own "Dəstək"
 * row with its unread badge, a contextual button, an automatic flow, the optional launcher, and closing from code.
 * The full sample is CM-076's.
 */
class MainActivity : Activity() {
    private lateinit var badge: TextView
    private lateinit var log: TextView
    private val unread = UnreadCountListener { count ->
        badge.visibility = if (count > 0) View.VISIBLE else View.GONE
        badge.text = if (count > 99) "99+" else count.toString()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val padding = (16 * resources.displayMetrics.density).toInt()
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
        }
        column.addView(TextView(this).apply {
            setText(R.string.profile)
            textSize = 28f
        })

        // The app's own button and badge: Clomni adds nothing to this screen by itself.
        val supportRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        supportRow.addView(button(R.string.support) { Clomni.present(source = "profile_support") })
        badge = TextView(this).apply {
            setTextColor(0xFFFFFFFF.toInt())
            setBackgroundColor(0xFFE5484D.toInt())
            setPadding(padding / 2, 0, padding / 2, 0)
            visibility = View.GONE
        }
        supportRow.addView(badge)
        column.addView(supportRow)

        column.addView(button(R.string.new_conversation) { Clomni.presentNewConversation(source = "profile_new") })
        // Contextual: the conversation starts with the ride it is about.
        column.addView(button(R.string.report_problem) {
            Clomni.startFlow("ride_problem", mapOf("ride_id" to "R-1923"), openMessenger = true, source = "ride_screen")
        })
        // Automatic: the app reacts to its own event; the flow decides what to say.
        column.addView(button(R.string.payment_failed) {
            Clomni.startFlow("payment_failed", mapOf("order_id" to "A-1042", "amount" to 2.4), openMessenger = true)
        })
        column.addView(Switch(this).apply {
            setText(R.string.launcher)
            setOnCheckedChangeListener { _, on -> Clomni.setLauncherVisible(on) }
        })
        // What the app's FirebaseMessagingService does (android/docs/push.md), with a payload made here: the sample
        // has no Firebase.
        column.addView(button(R.string.fake_push) {
            ClomniPush.handle(
                this,
                mapOf(
                    "clomni" to "1", "type" to "message", "conversation_id" to "conv_sample", "message_id" to "msg_1",
                    "title" to "Leyla · Apar", "body" to "Gedişinizi yoxladıq, balansınıza 2 AZN qaytarıldı.",
                    "avatar_url" to "https://app.clomni.ai/a/leyla.png", "unread_total" to "1",
                ),
            )
        })
        column.addView(button(R.string.own_push) {
            val handled = ClomniPush.handle(this, mapOf("order_id" to "A-1042", "title" to "Sifarişiniz yoldadır"))
            note(if (handled) "Clomni push" else "the app's own push: ClomniPush.handle returned false")
        })
        column.addView(button(R.string.close_in_3) {
            Clomni.present(source = "dismiss_demo")
            Handler(Looper.getMainLooper()).postDelayed({ Clomni.dismiss() }, 3_000)
        })

        column.addView(TextView(this).apply {
            setText(R.string.events)
            setPadding(0, padding, 0, 0)
        })
        log = TextView(this)
        column.addView(log)
        setContentView(ScrollView(this).apply { addView(column) })

        Clomni.onMessengerOpened { source -> note("opened ($source)") }
        Clomni.onMessengerClosed { note("closed") }
        Clomni.onConversationStarted { id -> note("conversation $id") }
        Clomni.onFlowCompleted { flow -> note("flow completed: $flow") }

        // Android 13+: notifications need the user's yes, asked by the app.
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    override fun onStart() {
        super.onStart()
        Clomni.addUnreadCountListener(unread)
    }

    override fun onStop() {
        Clomni.removeUnreadCountListener(unread)
        super.onStop()
    }

    private fun button(text: Int, action: () -> Unit) = Button(this).apply {
        setText(text)
        setOnClickListener { action() }
    }

    private fun note(line: String) {
        log.append("$line\n")
    }
}
