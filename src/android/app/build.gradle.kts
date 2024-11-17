import java.io.IOException

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

fun String.runCommand(workingDir: File = File(".")): String? {
    try {
        val proc = ProcessBuilder(*trim().split("\\s".toRegex()).toTypedArray())
            .directory(workingDir)
            .redirectOutput(ProcessBuilder.Redirect.PIPE)
            .redirectError(ProcessBuilder.Redirect.PIPE)
            .start()
        proc.waitFor(1, TimeUnit.MINUTES)
        return proc.inputStream.bufferedReader().readText()
    } catch (e: IOException) {
        e.printStackTrace()
        return null
    }
}

fun getGitHash(): String? = "git log --format=%h -1".runCommand()?.trim()

val versionMajor: String? = System.getenv("EMULATOR_VERSION_MAJOR")
val versionMinor: String? = System.getenv("EMULATOR_VERSION_MINOR")

fun getVersionName(): String {
    if (versionMajor != null && versionMinor != null)
        return "$versionMinor.$versionMinor"
    return getGitHash() ?: "1.0"
}

fun getVersionCode(): Int = System.getenv("VERSION_CODE")?.toIntOrNull() ?: 1

android {
    namespace = "info.cemu.cemu"
    compileSdk = 35
    ndkVersion = "26.1.10909125"
    defaultConfig {
        applicationId = "info.cemu.cemu"
        minSdk = 30
        targetSdk = 35
        versionCode = getVersionCode()
        versionName = getVersionName()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    val keystoreFilePath: String? = System.getenv("ANDROID_KEYSTORE_FILE")
    signingConfigs {
        if (keystoreFilePath != null) {
            signingConfigs {
                create("release") {
                    storeFile = file(keystoreFilePath)
                    storePassword = System.getenv("ANDROID_KEY_STORE_PASSWORD")
                    keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                    keyPassword = System.getenv("ANDROID_KEYSTORE_PASS")
                }
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (keystoreFilePath != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        debug {
            applicationIdSuffix = ".debug"
        }
    }
    compileOptions {
        sourceCompatibility(JavaVersion.VERSION_17)
        targetCompatibility(JavaVersion.VERSION_17)
    }
    externalNativeBuild {
        cmake {
            version = "3.22.1"
            path = file("../../../CMakeLists.txt")
        }
    }
    val versionArguments = if (versionMajor != null && versionMinor != null)
        arrayOf(
            "-DEMULATOR_VERSION_MAJOR=$versionMajor",
            "-DEMULATOR_VERSION_MINOR=$versionMinor"
        ) else emptyArray()
    val cmakeArguments = arrayOf(
        "-DANDROID_STL=c++_shared",
        "-DENABLE_VCPKG=ON",
        "-DVCPKG_TARGET_ANDROID=ON",
        "-DENABLE_SDL=OFF",
        "-DENABLE_WXWIDGETS=OFF",
        "-DENABLE_OPENGL=OFF",
        "-DBUNDLE_SPEEX=ON",
        "-DENABLE_DISCORD_RPC=OFF",
        "-DENABLE_NSYSHID_LIBUSB=OFF",
        "-DENABLE_WAYLAND=OFF",
        "-DENABLE_HIDAPI=OFF"
    ) + versionArguments
    defaultConfig {
        externalNativeBuild {
            cmake {
                arguments(
                    *cmakeArguments
                )
                abiFilters("arm64-v8a")
            }
        }
    }
    buildFeatures {
        buildConfig = true
        dataBinding = true
        viewBinding = true
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation(libs.androidx.datastore.rxjava3)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.androidx.datastore)
    implementation(libs.okhttp)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.swiperefreshlayout)
    implementation(libs.androidx.navigation.fragment)
    implementation(libs.androidx.navigation.ui)
    implementation(libs.androidx.legacy.support.v4)
    implementation(libs.androidx.lifecycle.livedata.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.androidx.core.ktx)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}
