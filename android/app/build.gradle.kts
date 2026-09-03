import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use(::load)
}

fun localConfig(name: String): String = localProperties.getProperty(name, "").trim()

val revenueCatApiKey = localConfig("REVENUECAT_ANDROID_API_KEY")
val honouredWebAppUrl = localConfig("HONOURED_WEB_APP_URL")

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
