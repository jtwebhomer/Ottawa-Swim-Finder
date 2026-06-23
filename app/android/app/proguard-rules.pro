# WorkManager uses Room internally; R8 must keep generated DB implementation classes.
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.InputMerger
-keep class androidx.work.WorkManagerInitializer
-keep class androidx.work.impl.** { *; }
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-keepclassmembers class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}

# Flutter background worker entry point
-keep class dev.fluttercommunity.workmanager.** { *; }

# ObjectBox (map tile cache backend)
-keep class io.objectbox.** { *; }
-keep class net.objectbox.** { *; }
-keepattributes *Annotation*
-dontwarn io.objectbox.**

# SQLite / sqflite
-keep class com.tekartik.sqflite.** { *; }
