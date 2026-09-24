pluginManagement {
    val gpuBuild = providers.gradleProperty("dart-defines").orNull.orEmpty()
        .split(",").filter { it.isNotBlank() }
        .map { String(java.util.Base64.getDecoder().decode(it)) }
        .contains("KRAKEN_S24_GPU=true")
    resolutionStrategy {
        eachPlugin {
            if (gpuBuild && requested.id.id == "org.jetbrains.kotlin.android") useVersion("2.4.20")
        }
    }

    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
