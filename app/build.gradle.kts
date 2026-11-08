plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// The game lives in index.html and models/ at the repo root (so it also works on a web server).
// Copy it into the APK's assets at build time.
val webAssetsDir = layout.buildDirectory.dir("generated/webassets")
val copyWebAssets by tasks.registering(Copy::class) {
    from(rootProject.projectDir) {
        include("index.html", "models/**")
    }
    into(webAssetsDir)
}

android {
    namespace = "com.abrar.dustsignal"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.abrar.dustsignal"
        minSdk = 24
        targetSdk = 34
        // CI sets VERSION_CODE to the run number so every build installs as an update
        versionCode = (System.getenv("VERSION_CODE") ?: "1").toInt()
        versionName = "1.0.${System.getenv("VERSION_CODE") ?: "0"}"
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

    sourceSets {
        getByName("main") {
            assets.srcDir(webAssetsDir)
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

tasks.named("preBuild") {
    dependsOn(copyWebAssets)
}

dependencies {
    implementation("androidx.webkit:webkit:1.11.0")
}
