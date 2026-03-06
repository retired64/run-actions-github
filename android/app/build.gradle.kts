import java.util.Properties
import java.io.FileInputStream
import com.android.build.gradle.internal.api.ApkVariantOutputImpl

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

/*
|--------------------------------------------------------------------------
| Keystore loading (safe for open-source)
|--------------------------------------------------------------------------
*/
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace    = "com.retired64.githubactions"
    compileSdk   = flutter.compileSdkVersion
    ndkVersion   = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    /*
    |--------------------------------------------------------------------------
    | Signing configuration (always created, safe fallback if key.properties
    | is absent — values will be empty strings and signing will be skipped)
    |--------------------------------------------------------------------------
    */
    signingConfigs {
        create("release") {
            keyAlias      = keystoreProperties["keyAlias"]      as? String ?: ""
            keyPassword   = keystoreProperties["keyPassword"]   as? String ?: ""
            storeFile     = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as? String ?: ""
        }
    }

    defaultConfig {
        applicationId = "com.retired64.githubactions"
        minSdk        = flutter.minSdkVersion
        targetSdk     = flutter.targetSdkVersion
        versionCode   = flutter.versionCode
        versionName   = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled    = true
            isShrinkResources  = true
        }
    }
}

flutter {
    source = "../.."
}

/*
|--------------------------------------------------------------------------
| ABI versionCode logic (for split-per-abi builds)
|--------------------------------------------------------------------------
*/
val abiCodes = mapOf(
    "armeabi-v7a" to 1,
    "arm64-v8a"   to 2,
    "x86_64"      to 3
)

android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        val abiVersionCode =
            abiCodes[output.filters.find { it.filterType == "ABI" }?.identifier]
        if (abiVersionCode != null) {
            (output as ApkVariantOutputImpl).versionCodeOverride =
                variant.versionCode * 10 + abiVersionCode
        }
    }
}