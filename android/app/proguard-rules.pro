# R8 rules for the release and smoke builds.

# The page calls these by name through addJavascriptInterface (HonouredNative).
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Credential Manager finds its Play Services provider by reflection.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** {
    *;
}

# Readable stack traces in Play Console without shipping file names.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
