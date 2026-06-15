package app.pguard.mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not the default FlutterActivity) is required by the `local_auth`
// plugin: the biometric prompt is hosted in a fragment, so the host activity must be a
// FragmentActivity. Everything else about the activity stays the Flutter default.
class MainActivity : FlutterFragmentActivity()
