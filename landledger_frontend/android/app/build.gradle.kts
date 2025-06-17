plugins {
    id("com.android.application")
    id("kotlin-android")
    // ✅ Mapbox SDK may require this for certain features
    id("kotlin-parcelize") 
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

repositories {
    google()
    mavenCentral()
    maven {
        url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
        credentials {
            username = "mapbox"
            password = project.findProperty("pk.eyJ1IjoibW9yZ25jb2x0IiwiYSI6ImNtYng2eHI0ZjB3cjQybW9zNXZhaDJqanYifQ.0qZEU6MBjiTZiUDPs6JyoQ") as String?
        }
    }
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
    // ✅ Required for Mapbox (Java/Kotlin side of SDK)
    implementation("com.mapbox.maps:android:10.15.1")

    // Optional: Jetpack support if you use lifecycle-aware components
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.6.2")
}




