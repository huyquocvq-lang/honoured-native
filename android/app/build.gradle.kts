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
// Public Supabase URL and anon key, for the native session refresh. Empty turns
// the native session off (capabilities.sessionRefresh.supported: false).
val supabaseUrl = env("SUPABASE_URL")
val supabaseAnonKey = env("SUPABASE_ANON_KEY")
if (revenueCatEntitlementId.isNotEmpty()) {
    logger.lifecycle(
        "warning: REVENUECAT_ENTITLEMENT_ID=$revenueCatEntitlementId — this build checks a " +
            "non-production entitlement. Clear it before building a release for the store.",
    )
}

// Tracked version: bump VERSION_CODE for every upload to Play.
val versionProperties = loadProperties(rootProject.file("version.properties"))
val appVersionName: String = versionProperties.getProperty("VERSION_NAME")?.trim().orEmpty()
    .ifEmpty { throw GradleException("android/version.properties: VERSION_NAME is missing") }
val appVersionCode: Int = versionProperties.getProperty("VERSION_CODE")?.trim()?.toIntOrNull()
    ?: throw GradleException("android/version.properties: VERSION_CODE is missing or not a number")

// Upload key for store builds. Never in the repository: android/local.properties
// (gitignored) or the environment, e.g. on a CI runner.
fun secret(name: String): String =
    (localProperties.getProperty(name) ?: System.getenv(name) ?: "").trim()

val uploadStoreFile = secret("HONOURED_UPLOAD_STORE_FILE")
val uploadStorePassword = secret("HONOURED_UPLOAD_STORE_PASSWORD")
val uploadKeyAlias = secret("HONOURED_UPLOAD_KEY_ALIAS")
val uploadKeyPassword = secret("HONOURED_UPLOAD_KEY_PASSWORD")
val uploadKeyReady = listOf(uploadStoreFile, uploadStorePassword, uploadKeyAlias, uploadKeyPassword)
    .all { it.isNotEmpty() } && file(uploadStoreFile).isFile

/** Everything a store build needs; empty when a release may be built. */
fun releaseProblems(): List<String> = buildList {
    if (!uploadKeyReady) {
        add(
            "upload key: set HONOURED_UPLOAD_STORE_FILE (an existing keystore), HONOURED_UPLOAD_STORE_PASSWORD, " +
                "HONOURED_UPLOAD_KEY_ALIAS and HONOURED_UPLOAD_KEY_PASSWORD in android/local.properties or the environment",
        )
    }
    if (revenueCatEntitlementId.isNotEmpty()) add("REVENUECAT_ENTITLEMENT_ID must be empty for a store build")
    if (!honouredWebAppUrl.startsWith("https://")) add("HONOURED_WEB_APP_URL must be an https:// URL")
    if (revenueCatApiKey.isEmpty()) add("REVENUECAT_ANDROID_API_KEY is empty")
    if (googleWebClientId.isEmpty()) add("GOOGLE_WEB_CLIENT_ID is empty")
    if (!supabaseUrl.startsWith("https://")) add("SUPABASE_URL must be an https:// URL")
    if (supabaseAnonKey.isEmpty()) add("SUPABASE_ANON_KEY is empty")
}

android {
    namespace = "com.honoured.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.honoured.app"
        minSdk = 26
        targetSdk = 35
        versionCode = appVersionCode
        versionName = appVersionName
        buildConfigField("String", "REVENUECAT_ANDROID_API_KEY", "\"$revenueCatApiKey\"")
        buildConfigField("String", "HONOURED_WEB_APP_URL", "\"$honouredWebAppUrl\"")
        buildConfigField("String", "REVENUECAT_ENTITLEMENT_ID", "\"$revenueCatEntitlementId\"")
        buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", "\"$googleWebClientId\"")
        buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrl\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseAnonKey\"")
        // Smoke builds only: lets chrome://inspect reach the WebView of an R8 build.
        buildConfigField("boolean", "WEBVIEW_DEBUGGING", "false")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (uploadKeyReady) {
            create("release") {
                storeFile = file(uploadStoreFile)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Null without an upload key; the release guard below refuses the build first.
            signingConfig = signingConfigs.findByName("release")
        }
        // The release build (R8, shrinking, same package and config) signed with
        // the debug key, to smoke-test on a device or emulator. Play refuses
        // debug-signed uploads, so it can never reach the store by mistake.
        create("smoke") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += "release"
            buildConfigField("boolean", "WEBVIEW_DEBUGGING", "true")
        }
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

// A store build never goes out unsigned, with a test entitlement, or without
// its configuration. Debug and smoke builds are not affected.
gradle.taskGraph.whenReady {
    val releaseTasks = allTasks.filter { task ->
        task.project == project && task.name.endsWith("Release") &&
            listOf("assemble", "bundle", "package", "sign").any { task.name.startsWith(it) }
    }
    if (releaseTasks.isEmpty()) return@whenReady
    val problems = releaseProblems()
    if (problems.isNotEmpty()) {
        throw GradleException("Refusing to build a store release:\n - " + problems.joinToString("\n - "))
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
    // Android's org.json is a stub in local unit tests.
    testImplementation("org.json:json:20240303")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}
