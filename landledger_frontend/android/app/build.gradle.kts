plugins {
    id("com.android.application")
    id("kotlin-android")
    // ✅ Mapbox SDK may require this for certain features
    id("kotlin-parcelize") 
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.landledger_frontend"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // ✅ Explicitly override NDK version

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.landledger_frontend"
        minSdk = 23 // ✅ Satisfies Mapbox + Firebase
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own release signing config
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        viewBinding = true // Optional, good for UI work
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.5.0"))
    implementation("com.google.firebase:firebase-appcheck-debug")
    implementation("com.google.firebase:firebase-dynamic-links:21.2.0")
    // ✅ Required for Mapbox (Java/Kotlin side of SDK)
    implementation("com.mapbox.maps:android:10.15.1")

    // Optional: Jetpack support if you use lifecycle-aware components
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.6.2")
}




