package ai.clomni.messenger.sample

import ai.clomni.messenger.Clomni
import ai.clomni.messenger.ClomniUser
import ai.clomni.messenger.UnreadCountListener
import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.Switch
import android.widget.TextView

/** The app's profile screen: its own "Dəstək" row is the way into the messenger. Clomni adds nothing here itself. */
class MainActivity : Activity() {
    private lateinit var supportBadge: TextView
    private lateinit var events: TextView

    // The unread count on the app's own "Dəstək" row.
    private val unread = UnreadCountListener { count ->
        supportBadge.visibility = if (count > 0) View.VISIBLE else View.GONE
        supportBadge.text = count.toString()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        supportBadge = findViewById(R.id.support_badge)
        events = findViewById(R.id.events)

        // The app's own button opens the messenger; the source is stored with a conversation started there.
        findViewById<View>(R.id.support).setOnClickListener { Clomni.present(source = "profile_support") }

        // A contextual button: the conversation starts with the ride it is about.
        findViewById<View>(R.id.report_problem).setOnClickListener {
            Clomni.startFlow("ride_problem", mapOf("ride_id" to "R-1923"), openMessenger = true, source = "ride_screen")
        }

        // The floating button is off unless the app (or the Clomni panel) turns it on.
        findViewById<Switch>(R.id.launcher).setOnCheckedChangeListener { _, on -> Clomni.setLauncherVisible(on) }

        findViewById<View>(R.id.login).setOnClickListener { logIn() }
        findViewById<View>(R.id.logout).setOnClickListener { logOut() }
        findViewById<View>(R.id.fake_push).setOnClickListener { FakePush.deliver(this) }

        Clomni.onConversationStarted { id -> note("conversation $id started") }
        Clomni.onMessengerClosed { note("messenger closed") }

        // Android 13+: Clomni's notifications need the user's permission, which the app asks for.
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

    private fun logIn() {
        // After the app's own login: its user, and the hash its server computed (DemoServer stands in for it).
        val userId = "12345"
        val user = ClomniUser(userId = userId, email = "aysel@example.com", name = "Aysel Məmmədova")
        Clomni.loginUser(user, userHash = DemoServer.userHash(userId))
        findViewById<TextView>(R.id.user).text = user.name
    }

    private fun logOut() {
        // With the app's own logout: the next user must not see this one's conversations.
        Clomni.logout()
        findViewById<TextView>(R.id.user).text = ""
    }

    private fun note(line: String) {
        events.append("$line\n")
    }
}
