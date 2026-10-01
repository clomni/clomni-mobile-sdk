package ai.clomni.messenger.sample

import android.app.Activity
import android.os.Bundle
import android.widget.TextView

// Placeholder screen so the module builds against the SDK; the real sample arrives with the public API (CM-076).
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply { setText(R.string.app_name) })
    }
}
