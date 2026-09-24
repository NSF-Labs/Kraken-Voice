import java.util.Base64
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// One explicit build switch selects matching Dart and native profiles.
val gpuBuild = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(",").filter { it.isNotBlank() }
    .map { String(Base64.getDecoder().decode(it)) }
    .contains("KRAKEN_S24_GPU=true")

// Load key.properties for release signing
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    sourceSets.getByName("main").java.srcDir(if (gpuBuild) "src/gpu/kotlin" else "src/npu/kotlin")
    namespace = "org.krak_en.voice"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }


    defaultConfig {
        applicationId = "org.krak_en.voice"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 31
        ndk { abiFilters += "arm64-v8a" }
        if (!gpuBuild) externalNativeBuild { cmake { arguments += "-DANDROID_STL=c++_static"; abiFilters += "arm64-v8a" } }
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (!gpuBuild) externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt") } }
    packaging { jniLibs {
        useLegacyPackaging = true
        keepDebugSymbols += "**/libggml-htp-*.so"
        if (gpuBuild) excludes += setOf("**/libggml*.so", "**/libllama.so", "**/libkraken_npu.so")
    } }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", if (gpuBuild) "Krak-EN Voice GPU" else "Krak-EN Voice")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", if (gpuBuild) "Krak-EN Voice GPU" else "Krak-EN Voice")
        }
    }

    buildTypes {
        release {
            // Never silently create a debug-signed public release.
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

flutter {
    source = "../.."
}

dependencies {
    if (gpuBuild) implementation("com.google.ai.edge.litertlm:litertlm-android:0.17.1")
    testImplementation("junit:junit:4.13.2")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

}

// Fail early on missing or changed binary dependencies; never fetch code at runtime.
val verifyHexagonRuntime by tasks.registering(Exec::class) {
    workingDir(rootProject.projectDir.parentFile)
    commandLine("python3", "scripts/prepare_hexagon_runtime.py", "--verify")
}
if (!gpuBuild) tasks.named("preBuild") { dependsOn(verifyHexagonRuntime) }

// Flutter supplies broad ABI defaults late in configuration. This runtime is ARM64-only.
androidComponents {
    finalizeDsl { extension ->
        extension.defaultConfig.ndk.abiFilters.clear()
        extension.defaultConfig.ndk.abiFilters.add("arm64-v8a")
    }
}
