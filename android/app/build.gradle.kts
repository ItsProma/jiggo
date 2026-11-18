import java.net.URI
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}
val signingFields = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val signingConfigured = signingFields.all { !signingProperties.getProperty(it).isNullOrBlank() }

// Dart defines here contain public release configuration only, never secrets.
val dartDefines = (providers.gradleProperty("dart-defines").orNull ?: "")
    .split(',')
    .filter { it.isNotBlank() }
    .mapNotNull { entry ->
        val decoded = runCatching { String(Base64.getDecoder().decode(entry), Charsets.UTF_8) }.getOrNull()
        val separator = decoded?.indexOf('=') ?: -1
        if (decoded != null && separator > 0) decoded.substring(0, separator) to decoded.substring(separator + 1) else null
    }.toMap()

android {
    namespace = "net.debcreatives.jiggo"
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "net.debcreatives.jiggo"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (signingConfigured) {
                storeFile = rootProject.file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // A release build must never fall back to the debug signing key.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter { source = "../.." }

gradle.taskGraph.whenReady {
    val releasing = allTasks.any { it.project.path == ":app" && it.name.contains("Release", ignoreCase = true) }
    if (releasing) {
        check(signingConfigured) { "Configure android/key.properties with your local upload keystore before building release." }
        check(rootProject.file(signingProperties.getProperty("storeFile")).isFile) { "Release upload keystore file was not found." }
        check(dartDefines["APP_CHECK_DEBUG_TOKEN"].isNullOrBlank()) {
            "Do not include an App Check debug token in release builds. Use release-config.json."
        }
        check(dartDefines["ENABLE_PRODUCTION_ADS"] != "true") {
            "This release does not include advertising. Remove ENABLE_PRODUCTION_ADS=true."
        }
        for (name in listOf("PRIVACY_POLICY_URL", "ACCOUNT_DELETION_URL")) {
            val url = dartDefines[name] ?: ""
            val uri = runCatching { URI(url) }.getOrNull()
            check(uri != null && uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo.isNullOrEmpty()) {
                "Provide a public HTTPS $name before release."
            }
        }
        check((dartDefines["SUPPORT_EMAIL"] ?: "").matches(Regex("[^\\s@]+@[^\\s@]+\\.[^\\s@]+"))) {
            "Provide a public SUPPORT_EMAIL before release."
        }
    }
}

// Required by the local notification plugin.
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
