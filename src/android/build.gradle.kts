// MuffinEMU for Android. The core (libCemu.so) is built by CMake with the NDK (ci/build-core-android.sh)
// and dropped into app/src/main/jniLibs; this Gradle project only builds the Kotlin app around it.
plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
}
