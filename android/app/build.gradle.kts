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
val revenueCatEntitlementId = env("REVENUECAT_ENTITLEMENT_ID")
// Public Web application client ID: the audience of Google ID tokens. Empty
// turns Google Sign-In off (capability configured: false).
val googleWebClientId = env("GOOGLE_WEB_CLIENT_ID")
if (revenueCatEntitlementId.isNotEmpty()) {
    logger.lifecycle(
        "warning: REVENUECAT_ENTITLEMENT_ID=$revenueCatEntitlementId — this build checks a " +
            "non-production entitlement. Clear it before building a release for the store.",
    )
}

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
        buildConfigField("String", "REVENUECAT_ENTITLEMENT_ID", "\"$revenueCatEntitlementId\"")
        buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", "\"$googleWebClientId\"")
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

    // Google Sign-In through Credential Manager (no Firebase, no
    // google-services.json). Stable releases that compile against SDK 35.
    implementation("androidx.credentials:credentials:1.5.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.5.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")
    // Origin-scoped WebMessageListener transport for the auth bridge.
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    testImplementation("junit:junit:4.13.2")
}
