import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Machine-specific configuration. The repository-root .env is the shared
// source of truth for both native shells; android/local.properties may
// override any key for this machine only. Both files are gitignored.
fun loadProperties(file: File): Properties = Properties().apply {
    if (file.exists()) file.inputStream().use(::load)
}

val envProperties = loadProperties(rootProject.file("../.env"))
val localProperties = loadProperties(rootProject.file("local.properties"))

// local.properties wins: it is the narrower, Android-only scope.
fun env(name: String): String =
    (localProperties.getProperty(name) ?: envProperties.getProperty(name) ?: "").trim()

val revenueCatApiKey = env("REVENUECAT_ANDROID_API_KEY")
val honouredWebAppUrl = env("HONOURED_WEB_APP_URL")

android {
    namespace = "com.honoured.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.honoured.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
        buildConfigField("String", "REVENUECAT_ANDROID_API_KEY", "\"$revenueCatApiKey\"")
        buildConfigField("String", "HONOURED_WEB_APP_URL", "\"$honouredWebAppUrl\"")
    }

    buildFeatures {
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
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.activity:activity-ktx:1.10.0")
    implementation("com.revenuecat.purchases:purchases:10.16.0")
}
