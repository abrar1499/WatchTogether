package com.abrar.watchtogether

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions

class WatchApp : Application() {

    override fun onCreate() {
        super.onCreate()
        RemoteConfig.init(this)   // instant from the saved copy; refreshes quietly in the background
        if (isFirebaseConfigured() && FirebaseApp.getApps(this).isEmpty()) {
            try {
                val builder = FirebaseOptions.Builder()
                    .setApplicationId(BuildConfig.FIREBASE_APP_ID)
                    .setProjectId(BuildConfig.FIREBASE_PROJECT_ID)
                    .setDatabaseUrl(BuildConfig.FIREBASE_DB_URL)
                // API key is optional for Realtime Database with open rules
                if (BuildConfig.FIREBASE_API_KEY.isNotBlank()) {
                    builder.setApiKey(BuildConfig.FIREBASE_API_KEY)
                }
                val options = builder.build()
                FirebaseApp.initializeApp(this, options)
            } catch (e: Exception) {
                Log.e("WatchApp", "Firebase init failed", e)
            }
        }
    }

    companion object {
        fun isFirebaseConfigured(): Boolean =
            BuildConfig.FIREBASE_APP_ID.isNotBlank() &&
                BuildConfig.FIREBASE_DB_URL.isNotBlank()
    }
}
