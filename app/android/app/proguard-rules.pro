# ─────────────────────────────────────────────────────────────────────────────
#  proguard-rules.pro — Xissin App
#  Applied during: flutter build apk --release
#  Combined with:  proguard-android-optimize.txt (from getDefaultProguardFile)
#  Also use:       --obfuscate flag to rename Dart symbols
# ─────────────────────────────────────────────────────────────────────────────

# ── Flutter engine (never obfuscate) ─────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.util.** { *; }
-dontwarn io.flutter.**

# ── Flutter secure storage ────────────────────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# ── Google Mobile Ads (AdMob) ─────────────────────────────────────────────────
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# ── Google Play Services ──────────────────────────────────────────────────────
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ── OkHttp / networking ───────────────────────────────────────────────────────
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# ── Kotlin ────────────────────────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}

# ── AndroidX / Support ────────────────────────────────────────────────────────
-keep class androidx.** { *; }
-dontwarn androidx.**
-keep class android.support.** { *; }
-dontwarn android.support.**

# ── Geolocator ────────────────────────────────────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# ── Permission handler ────────────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# ── Package info ──────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-dontwarn dev.fluttercommunity.plus.packageinfo.**

# ── Device info ───────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.device_info.** { *; }
-dontwarn dev.fluttercommunity.plus.device_info.**

# ── Connectivity ─────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.connectivity.** { *; }
-dontwarn dev.fluttercommunity.plus.connectivity.**

# ── Battery ───────────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.battery.** { *; }
-dontwarn dev.fluttercommunity.plus.battery.**

# ── URL launcher ─────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.urllauncher.** { *; }
-dontwarn io.flutter.plugins.urllauncher.**

# ── WebView ───────────────────────────────────────────────────────────────────
-keep class io.flutter.plugins.webviewflutter.** { *; }
-dontwarn io.flutter.plugins.webviewflutter.**

# ── File picker ───────────────────────────────────────────────────────────────
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**

# ── Share plus ────────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.share.** { *; }
-dontwarn dev.fluttercommunity.plus.share.**

# ── Open file ─────────────────────────────────────────────────────────────────
-keep class com.crazecoder.openfile.** { *; }
-dontwarn com.crazecoder.openfile.**

# ── Crypto (JVM) ─────────────────────────────────────────────────────────────
-keep class javax.crypto.** { *; }
-keep class java.security.** { *; }

# ── Enum classes (needed for correct behaviour) ───────────────────────────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ── Parcelable ────────────────────────────────────────────────────────────────
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# ── Serialization ─────────────────────────────────────────────────────────────
-keepclassmembers class * implements java.io.Serializable {
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ── Native methods ────────────────────────────────────────────────────────────
-keepclasseswithmembernames class * {
    native <methods>;
}

# ── Remove logging in release ─────────────────────────────────────────────────
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# ── Suppress common harmless warnings ────────────────────────────────────────
-dontwarn java.lang.invoke.**
-dontwarn **$$serializer
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
