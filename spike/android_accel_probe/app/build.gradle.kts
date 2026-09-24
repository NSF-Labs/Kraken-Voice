plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Pin for reproducible spike measurements (matches prod floating latest.release target).
val litertLmVersion = "0.15.0"

android {
    namespace = "org.krak_en.spike"
    compileSdk = 36

    defaultConfig {
        applicationId = "org.krak_en.spike.accel"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "0.0.1-spike"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

dependencies {
    implementation("com.google.ai.edge.litertlm:litertlm-android:$litertLmVersion")
    // Must match litertlm's kotlinx-coroutines (1.9.0); 1.10.x causes NoSuchMethodError in Flow collect.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
