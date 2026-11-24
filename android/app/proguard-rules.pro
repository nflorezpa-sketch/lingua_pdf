# ML Kit (traducción e identificación de idioma) y sus plugins de Flutter:
# R8 los eliminaba en release y el canal nativo dejaba de responder.
-keep class com.google_mlkit_translation.** { *; }
-keep class com.google_mlkit_language_id.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**
# Voz (TTS)
-keep class com.eyedeadevelopment.fluttertts.** { *; }
