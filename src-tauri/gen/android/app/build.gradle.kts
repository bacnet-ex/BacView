import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("rust")
}

val tauriProperties = Properties().apply {
    val propFile = file("tauri.properties")
    if (propFile.exists()) {
        propFile.inputStream().use { load(it) }
    }
}

// Release signing: keystore.properties (gitignored) or BACVIEW_ANDROID_* env vars.
// See keystore.properties.example and scripts/android_create_keystore.sh.
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

fun propOrEnv(propKey: String, envKey: String): String? =
    keystoreProperties.getProperty(propKey)?.takeIf { it.isNotBlank() }
        ?: System.getenv(envKey)?.takeIf { it.isNotBlank() }

val releaseStoreFilePath = propOrEnv("storeFile", "BACVIEW_ANDROID_STORE_FILE")
val releaseStorePassword = propOrEnv("storePassword", "BACVIEW_ANDROID_STORE_PASSWORD")
val releaseKeyAlias = propOrEnv("keyAlias", "BACVIEW_ANDROID_KEY_ALIAS")
val releaseKeyPassword = propOrEnv("keyPassword", "BACVIEW_ANDROID_KEY_PASSWORD")

val releaseStoreFile: File? = releaseStoreFilePath?.let { path ->
    val f = File(path)
    if (f.isAbsolute) f else rootProject.file(path)
}

val hasReleaseKeystore =
    releaseStoreFile != null &&
        releaseStoreFile.isFile &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

android {
    compileSdk = 36
    namespace = "com.bacnet_ex.bacview"
    defaultConfig {
        manifestPlaceholders["usesCleartextTraffic"] = "false"
        applicationId = "com.bacnet_ex.bacview"
        minSdk = 24
        targetSdk = 36
        versionCode = tauriProperties.getProperty("tauri.android.versionCode", "1").toInt()
        versionName = tauriProperties.getProperty("tauri.android.versionName", "1.0")
    }
    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }
    buildTypes {
        getByName("debug") {
            manifestPlaceholders["usesCleartextTraffic"] = "true"
            isDebuggable = true
            isJniDebuggable = true
            isMinifyEnabled = false
            packaging {
                jniLibs.keepDebugSymbols.add("*/arm64-v8a/*.so")
                jniLibs.keepDebugSymbols.add("*/armeabi-v7a/*.so")
                jniLibs.keepDebugSymbols.add("*/x86/*.so")
                jniLibs.keepDebugSymbols.add("*/x86_64/*.so")
            }
        }
        getByName("release") {
            // Phoenix serves http://127.0.0.1 inside the WebView.
            manifestPlaceholders["usesCleartextTraffic"] = "true"
            isMinifyEnabled = true
            proguardFiles(
                *fileTree(".") { include("**/*.pro") }
                    .plus(getDefaultProguardFile("proguard-android-optimize.txt"))
                    .toList().toTypedArray()
            )
            // Prefer a real upload/release keystore. Fall back to the Android
            // debug key so local `mobile.android.build` APKs are installable
            // (unsigned release APKs fail with INSTALL_PARSE_FAILED_NO_CERTIFICATES).
            signingConfig = if (hasReleaseKeystore) {
                println("Using release keystore: ${releaseStoreFile!!.absolutePath}")
                signingConfigs.getByName("release")
            } else {
                println(
                    "WARNING: No release keystore configured " +
                        "(src-tauri/gen/android/keystore.properties or BACVIEW_ANDROID_*). " +
                        "Signing release with the debug key — fine for emulator/sideload, " +
                        "not for Play Store. See keystore.properties.example."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures {
        buildConfig = true
    }
    // Extract jniLibs to the filesystem so we can exec ERTS helpers (beam.smp,
    // erlexec, …) packaged as lib__*.so. Required for Android 10+ W^X.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

rust {
    rootDirRel = "../../../"
}

dependencies {
    implementation("androidx.webkit:webkit:1.14.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.lifecycle:lifecycle-process:2.10.0")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.4")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.0")
}

apply(from = "tauri.build.gradle.kts")