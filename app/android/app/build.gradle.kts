import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// O(1) —— release 签名配置读取
// key.properties 位于 app/android/（即 rootProject 目录），不入库。
// 文件缺失、storeFile 不存在或属性不全时自动回落到 debug 签名，保证任何人拉代码都能构建。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreProperties = keystorePropertiesFile.exists()
if (hasKeystoreProperties) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

val releaseStoreFilePath: String? =
    keystoreProperties.getProperty("storeFile")?.trim()?.takeIf { it.isNotEmpty() }
val releaseStoreFile: File? =
    releaseStoreFilePath?.let { rootProject.file(it) }?.takeIf { it.exists() }
val releaseKeyAlias: String? =
    keystoreProperties.getProperty("alias")?.trim()?.takeIf { it.isNotEmpty() }
val releaseStorePassword: String? =
    keystoreProperties.getProperty("storePassword")?.takeIf { it.isNotEmpty() }
val releaseKeyPassword: String? =
    keystoreProperties.getProperty("keyPassword")?.takeIf { it.isNotEmpty() }

val hasReleaseSigning: Boolean =
    releaseStoreFile != null && releaseKeyAlias != null &&
        releaseStorePassword != null && releaseKeyPassword != null

if (hasReleaseSigning) {
    logger.lifecycle("[signing] release keystore: ${releaseStoreFile?.absolutePath} (alias=${releaseKeyAlias})")
} else {
    logger.lifecycle("[signing] release keystore unavailable -> falling back to debug signing")
}

android {
    namespace = "cn.survey.survey_pro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "cn.survey.survey_pro"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                // 三种签名方案全部启用：v1(JAR) / v2(APK Signature Scheme v2) / v3
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = false
            }
        }
    }

    buildTypes {
        release {
            // key.properties + jks 都在位时用正式 release 签名，否则回落 debug 签名。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 交给 Flutter Gradle 插件按构建模式决定（release 默认开 R8 压缩与资源收缩）。
            // 显式写 false 会让 dex 从 ~1 MB 膨胀到 ~8.8 MB、res 全量保留。
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
