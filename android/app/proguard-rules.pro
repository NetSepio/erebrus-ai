# App-specific R8 rules. The Flutter Gradle plugin adds Flutter's own rules,
# and most plugins ship consumer rules or reach native code through FFI.

# flutter_local_notifications stores scheduled notifications as JSON through
# Gson 2.8.x, which ships no rules. Classes and fields may be renamed (the
# JSON is written and read by the same build), but R8 must keep the fields
# Gson fills, the generic signatures TypeToken reads, and enum constant names,
# which Gson looks up with getField(name()).
-keepattributes Signature
-keepclassmembers,allowobfuscation class com.dexterous.flutterlocalnotifications.models.** {
  <fields>;
  <init>();
}
-keepclassmembers enum com.dexterous.flutterlocalnotifications.models.** {
  <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
