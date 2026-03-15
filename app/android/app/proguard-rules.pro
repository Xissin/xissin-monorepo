# ══════════════════════════════════════════════════════════════════════════════
# Xissin App — proguard-rules.pro
# Aggressive obfuscation + protection rules
# ══════════════════════════════════════════════════════════════════════════════

# ── 1. Optimisation passes ────────────────────────────────────────────────────
-optimizationpasses 7
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses
-dontskipnonpubliclibraryclassmembers
-verbose
-allowaccessmodification
-mergeinterfacesaggressively

# Aggressive optimisations (R8 extended list)
-optimizations !code/simplification/cast,!field/*,!class/merging/*,\
               code/removal/simple,code/removal/advanced,\
               code/removal/exception,code/removal/string,\
               code/optimization/*

# ── 2. Keep Flutter engine (never obfuscate these) ───────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.app.** { *; }

# ── 3. Keep your app's entry point ───────────────────────────────────────────
-keep class com.xissin.app.MainActivity { *; }
-keep class com.xissin.app.** { *; }

# ── 4. Keep Kotlin metadata (required for reflection) ────────────────────────
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes Exceptions

-keep class kotlin.Metadata { *; }
-keep class kotlin.reflect.** { *; }
-dontwarn kotlin.**

# ── 5. Android components (must never be renamed) ────────────────────────────
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider
-keep public class * extends android.preference.Preference
-keep public class * extends android.view.View
-keep public class * extends androidx.** { *; }
-keep class androidx.lifecycle.** { *; }

# ── 6. Serialisation (Gson / JSON models) ────────────────────────────────────
# Keep field names used in JSON serialisation so responses still parse
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keep class * implements java.io.Serializable {
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object readResolve();
    java.lang.Object writeReplace();
}

# ── 7. Native methods ─────────────────────────────────────────────────────────
-keepclasseswithmembernames class * {
    native <methods>;
}

# ── 8. Enum classes ───────────────────────────────────────────────────────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ── 9. Parcelable ─────────────────────────────────────────────────────────────
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# ── 10. okhttp3 / http (used by Flutter http package) ────────────────────────
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okio.** { *; }

# ── 11. Google Play (in_app_purchase) ────────────────────────────────────────
-keep class com.google.android.gms.** { *; }
-keep class com.android.billingclient.** { *; }
-dontwarn com.google.android.gms.**

# ── 12. WebView (webview_flutter) ────────────────────────────────────────────
-keep class android.webkit.** { *; }
-keep class * extends android.webkit.WebViewClient { *; }
-keep class * extends android.webkit.WebChromeClient { *; }

# ── 13. Flutter Secure Storage ───────────────────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# ── 14. Package info plugin ───────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# ── 15. Device info plugin ────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.device_info.** { *; }

# ── 16. Connectivity plus ────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# ── 17. Suppress known harmless warnings ─────────────────────────────────────
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn sun.misc.**
-dontwarn java.lang.invoke.**
-dontwarn java.lang.reflect.**

# ── 18. REMOVE all logging in release ────────────────────────────────────────
# Strips Android Log calls — no stack traces or debug output in production
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int i(...);
    public static int w(...);
    public static int d(...);
    public static int e(...);
}
-assumenosideeffects class java.io.PrintStream {
    public void println(...);
    public void print(...);
}

# ── 19. String encryption hints ──────────────────────────────────────────────
# R8 will attempt to encrypt string constants with the below
-repackageclasses 'x'   # moves all classes into single package named 'x'
-flattenpackagehierarchy 'x'

# ── 20. Aggressive class renaming ─────────────────────────────────────────────
-obfuscationdictionary      proguard-dict.txt
-classobfuscationdictionary proguard-dict.txt
-packageobfuscationdictionary proguard-dict.txt
