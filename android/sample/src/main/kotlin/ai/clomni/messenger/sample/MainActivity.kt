package ai.clomni.messenger.sample

import ai.clomni.messenger.Clomni
import ai.clomni.messenger.UnreadCountListener
import android.app.Activity
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

        Clomni.onMessengerOpened = { source -> note("opened ($source)") }
        Clomni.onMessengerClosed = { note("closed") }
        Clomni.onConversationStarted = { id -> note("conversation $id") }
        Clomni.onFlowCompleted = { flow -> note("flow completed: $flow") }
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
