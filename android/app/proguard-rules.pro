# JNI entry points and streaming callback
-keep class org.krak_en.voice.HexagonBridge { *; }

# Keep Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# Keep Flutter Secure Storage crypto classes
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Keep AndroidX Security / Tink (used by flutter_secure_storage)
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }

# Keep FFmpegKit — native JNI bridge (crash: com.antonkarpenko.ffmpegkit.AbiDetect)
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.arthenica.mobileffmpeg.** { *; }
-keep class com.antonkarpenko.ffmpegkit.** { *; }

# Keep Sherpa ONNX native bridge
-keep class com.k2fsa.sherpa.onnx.** { *; }

# Keep permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# Keep sqflite / sqlcipher
-keep class com.tekartik.sqflite.** { *; }
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }

# Keep Flutter plugin registrants (narrowed — do NOT keep all of io.flutter.**)
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Don't warn about missing optional classes
-dontwarn com.it_nomads.fluttersecurestorage.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn com.arthenica.**
-dontwarn com.google.android.play.core.**
-dontwarn net.sqlcipher.**

# LiteRT-LM GPU variant JNI/reflection entry points
-keep class com.google.ai.edge.litertlm.** { *; }
