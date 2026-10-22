import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Firebase settings come from environment variables (GitHub Secrets on CI)
// or from local.properties when building on your own computer.
fun cfg(name: String, default: String = ""): String {
    val fromEnv = System.getenv(name)
    if (!fromEnv.isNullOrBlank()) return fromEnv
    val lp = rootProject.file("local.properties")
    if (lp.exists()) {
        val p = Properties()
        lp.inputStream().use { p.load(it) }
        val v = p.getProperty(name, "")
        if (v.isNotBlank()) return v
    }
    return default
}


android {
    namespace = "com.abrar.watchtogether"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.abrar.watchtogether"
        minSdk = 24
        targetSdk = 34
        // CI sets VERSION_CODE to the run number so every build installs as an update
        versionCode = (System.getenv("VERSION_CODE") ?: "1").toInt()
        versionName = "0.1.${System.getenv("VERSION_CODE") ?: "0"}"

        buildConfigField("String", "FIREBASE_API_KEY", "\"${cfg("FIREBASE_API_KEY")}\"")
        buildConfigField("String", "FIREBASE_APP_ID", "\"${cfg("FIREBASE_APP_ID")}\"")
        buildConfigField("String", "FIREBASE_PROJECT_ID", "\"${cfg("FIREBASE_PROJECT_ID")}\"")
        buildConfigField("String", "FIREBASE_DB_URL", "\"${cfg("FIREBASE_DB_URL")}\"")
    }

    signingConfigs {
        // Fixed key kept in the repo so every APK from CI installs over the old one
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")

    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-database")

}
