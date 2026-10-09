# A plugin bringing in WorkManager 2.7 with Room 2.2 (the ads SDK did), whose own keep rule
# doesn't keep the generated database's constructor. R8's full mode then
# removes it and release builds crash at launch ("Failed to create an
# instance of androidx.work.impl.WorkDatabase"), before Flutter starts.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
