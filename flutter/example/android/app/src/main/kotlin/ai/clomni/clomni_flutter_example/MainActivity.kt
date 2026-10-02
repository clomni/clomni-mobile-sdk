package ai.clomni.clomni_flutter_example

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity (brief 8 · 12): the messenger's launcher draws on the app's activity
// with Compose, which needs an AndroidX activity under it.
class MainActivity : FlutterFragmentActivity()
