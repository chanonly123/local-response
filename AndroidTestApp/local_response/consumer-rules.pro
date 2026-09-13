# Applied to every app that depends on this library.
#
# The payloads exchanged with the mapper are serialised by Gson, which matches
# JSON keys to field names by reflection. R8 renames fields it believes nothing
# reads, so without these rules a consumer's release build sends `{"a":...}`
# and the mapper silently records nothing useful — it still compiles and still
# runs.
#
# Note the absence of `allowobfuscation`, which the usual Gson snippet carries.
# That snippet is for models annotated with `@SerializedName`, where the JSON
# key survives renaming. These models have no annotations: the field name is
# the key, so renaming is exactly what has to be prevented. The class itself
# may still be renamed — Gson is handed the class, it does not look it up.
-keepclassmembers class com.chanonly123.local_response.URLTaskModelBegin { <fields>; }
-keepclassmembers class com.chanonly123.local_response.URLTaskModelUpdate { <fields>; }
-keepclassmembers class com.chanonly123.local_response.URLTaskModelEnd { <fields>; }
-keepclassmembers class com.chanonly123.local_response.MapCheckRequest { <fields>; }
-keepclassmembers class com.chanonly123.local_response.MapCheckResponse { <fields>; }

# Gson instantiates MapCheckResponse reflectively when a payload omits a field,
# bypassing the Kotlin constructor, so the no-arg path has to survive.
-keepclassmembers class com.chanonly123.local_response.MapCheckResponse {
    <init>(...);
}

# Created by the manifest, so nothing in the code references it by name.
-keep class com.chanonly123.local_response.LocalResponseInitializer { *; }
