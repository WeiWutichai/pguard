# Platform permissions — mic + camera (WebRTC calling)

This Flutter package ships `lib/` + `test/` only; the `android/` and `ios/` runners are generated
on demand with `flutter create .` (they are not committed). The WebRTC calling feature
(`flutter_webrtc` + `permission_handler`) needs the OS permission **declarations** below added to
those generated runners. The **runtime** requests are already made in code by
`lib/core/calling/webrtc_call_engine.dart` (`Permission.microphone` / `Permission.camera` before
`getUserMedia`), and `flutter_webrtc` itself prompts on first media access.

## Android — `android/app/src/main/AndroidManifest.xml`

Inside `<manifest>` (before `<application>`):

```xml
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />

<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<!-- Foreground call audio while screen off (optional, for long calls): -->
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

`minSdkVersion` must be **21+** for `flutter_webrtc`.

## iOS — `ios/Runner/Info.plist`

```xml
<key>NSMicrophoneUsageDescription</key>
<string>pguard ใช้ไมโครโฟนสำหรับการโทรด้วยเสียง / Microphone is used for voice calls.</string>
<key>NSCameraUsageDescription</key>
<string>pguard ใช้กล้องสำหรับวิดีโอคอล / Camera is used for video calls.</string>
```

Deployment target **12.0+** (flutter_webrtc). For background call audio, add `audio` to
`UIBackgroundModes` if/when CallKit/background calling is wired (not in this slice).

> Without these declarations the app crashes the first time the mic/camera is accessed on a real
> device. They are platform config, so they live here until the runners are generated.
