package com.example.landledger_frontend

import io.flutter.app.FlutterApplication
import com.google.firebase.FirebaseApp

class MainApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        // Initialize Firebase early to prevent initialization errors
        FirebaseApp.initializeApp(this)
    }
}
