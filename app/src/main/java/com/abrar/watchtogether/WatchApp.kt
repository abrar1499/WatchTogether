package com.abrar.watchtogether

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions

class WatchApp : Application() {

    override fun onCreate() {
        super.onCreate()
        if (isFirebaseConfigured() && FirebaseApp.getApps(this).isEmpty()) {
            try {
                val options = FirebaseOptions.Builder()
                    .setApiKey(BuildConfig.FIREBASE_API_KEY)
                    .setApplicationId(BuildConfig.FIREBASE_APP_ID)
                    .setProjectId(BuildConfig.FIREBASE_PROJECT_ID)
                    .setDatabaseUrl(BuildConfig.FIREBASE_DB_URL)
                    .build()
                FirebaseApp.initializeApp(this, options)
            } catch (e: Exception) {
                Log.e("WatchApp", "Firebase init failed", e)
            }
        }
    }

    companion object {
        fun isFirebaseConfigured(): Boolean =
            BuildConfig.FIREBASE_API_KEY.isNotBlank() &&
                BuildConfig.FIREBASE_APP_ID.isNotBlank() &&
                BuildConfig.FIREBASE_DB_URL.isNotBlank()
    }
}
