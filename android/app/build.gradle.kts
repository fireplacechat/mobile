import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fireplacechat.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fireplacechat.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing: android/key.properties (git-ignored; see docs/development/android-release.md).
    // Without it (CI, a fresh clone) the release build falls back to the debug key, which
    // is fine for checking that it builds but must never be distributed.
    //
    // A DISTRIBUTION build passes -Pfireplace.distribution=true and must never fall back: if the
    // signing material is missing or incomplete the build FAILS instead of producing a debug-signed
    // APK. (-Pfireplace.keyProperties=<file> points at another properties file; used by tests.)
    val distributionBuild = project.findProperty("fireplace.distribution") == "true"
    val keystoreProperties = Properties().apply {
        val override = project.findProperty("fireplace.keyProperties") as String?
        val f = if (override != null) file(override) else rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    if (distributionBuild) {
        val missing = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
            .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "Distribution build requested (-Pfireplace.distribution=true) but the signing " +
                    "material is missing or incomplete (${missing.joinToString()}). " +
                    "Refusing to fall back to the debug key; see docs/development/android-release.md."
            )
        }
    }
    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("WARNING: android/key.properties missing; signing the release build with the DEBUG key.")
                signingConfigs.getByName("debug")
            }
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
