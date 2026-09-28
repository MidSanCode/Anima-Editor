import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 签名材料由 CI 在构建时写到 android/key.properties（见 .github/workflows/build.yml），
// 该文件与 keystore 都在 android/.gitignore 里，绝不会进仓库。
// 本地没配这个文件时自动退回 debug 签名，`flutter run --release` 照样能跑。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.midsancode.anima.editor"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 全小写、无连字符，Android / iOS / 桌面三端通用，不再需要各端转写。
        applicationId = "com.midsancode.anima.editor"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // 有 key.properties 才建 release 签名配置；否则下面 buildTypes 走 debug。
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // 没有签名材料时用 debug 键，保证 `flutter run --release` 可用。
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// 引擎原生库（可选，走 AGP 默认约定，所以这里不需要写任何配置）：
// CI 把引擎 anima-android.aar 里的 jni/<abi>/libanima.so 放到
// app/src/main/jniLibs/<abi>/（见 .github/workflows/build.yml 的 android 作业），
// 而 src/main/jniLibs 本来就是 AGP 默认的 jniLibs 源目录，会随 APK 一起打包。
// 引擎 AAR 里的 classes.jar 是空壳（引擎没有 Java API，宿主自己 loadLibrary），
// 所以也不需要在 dependencies 里 implementation 那个 aar。
// 本地没有这个目录时构建照常通过，应用运行期自动降级到内置实现。

flutter {
    source = "../.."
}
