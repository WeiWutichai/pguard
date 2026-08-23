plugins {
    id("com.android.application")
    id("kotlin-android")
    // FCM — applies google-services.json (apps/mobile/android/app/) to the build. Must come after
    // the Android plugin.
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Matches the repo convention (apps/mobile/patrol.yaml package_name / bundle_id).
    namespace = "app.pguard.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (N3 check-in reminder sound) uses java.time APIs that must be
        // backported to our minSdk via core-library desugaring, or the release build fails to link.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "app.pguard.mobile"
        // flutter_webrtc requires minSdk >= 21; Flutter's default (flutter.minSdkVersion = 24)
        // already satisfies it, so we keep the managed default rather than pinning a lower value.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Backports java.time.* (used by flutter_local_notifications) to our minSdk. Required whenever
    // isCoreLibraryDesugaringEnabled = true.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
