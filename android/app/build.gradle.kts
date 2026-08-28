import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.erebrus.ai"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.erebrus.ai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Native llama.cpp uses APIs introduced in Android 9.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keyPropsFile = rootProject.file("key.properties")
            if (keyPropsFile.exists()) {
                val keyProps = Properties().apply {
                    keyPropsFile.inputStream().use { load(it) }
                }
                val storeFilePath = keyProps.getProperty("storeFile")
                if (!storeFilePath.isNullOrEmpty()) {
                    storeFile = file(storeFilePath)
                }
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            } else {
                val keystorePath = project.findProperty("ANDROID_KEYSTORE_PATH") as String?
                    ?: System.getenv("ANDROID_KEYSTORE_PATH")
                if (keystorePath != null && file(keystorePath).exists()) {
                    storeFile = file(keystorePath)
                    storePassword = project.findProperty("ANDROID_KEYSTORE_PASSWORD") as String?
                        ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
                    keyAlias = project.findProperty("ANDROID_KEY_ALIAS") as String?
                        ?: System.getenv("ANDROID_KEY_ALIAS")
                    keyPassword = project.findProperty("ANDROID_KEY_PASSWORD") as String?
                        ?: System.getenv("ANDROID_KEY_PASSWORD")
                }
            }
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.getByName("release")
            signingConfig = if (releaseSigning.storeFile != null && releaseSigning.storeFile!!.exists()) {
                releaseSigning
            } else {
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
