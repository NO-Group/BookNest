import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") apply false
}

// FCM activates the moment google-services.json is dropped in — the build
// stays green before that (push simply waits for the dashboard step).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.nogroup.booknest"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Store identity (Google Play, Firebase, Google Sign-In). The Kotlin
        // namespace below stays com.nogroup.booknest — only the id changes.
        applicationId = "com.n_o_group.booknest"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // camera plugin floor
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Stable release identity: the keystore in android/key is committed,
    // so CI and local builds share one signature and installs update in
    // place instead of Android treating each build as a different app.
    val keystoreProps = Properties().apply {
        val f = rootProject.file("key/booknest-keystore.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }

    signingConfigs {
        if (keystoreProps.isNotEmpty()) {
            create("booknestRelease") {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    // Google Play build (BN_PLAY=true, used for the .aab): drops the
    // background-link foreground service (see src/play/AndroidManifest.xml).
    if (System.getenv("BN_PLAY") == "true") {
        sourceSets.getByName("release").manifest.srcFile("src/play/AndroidManifest.xml")
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProps.isNotEmpty())
                signingConfigs.getByName("booknestRelease")
            else
                signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Push (FCM), used natively so the PC builds carry no Firebase SDK.
    // Without google-services.json Firebase simply stays uninitialized.
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("androidx.core:core:1.13.1")
}
