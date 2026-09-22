plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

/** Версия приложения: из параметра сборки, иначе для местной сборки. */
val appVersion: String = (project.findProperty("qpvpnVersion") as String?)
    ?.takeIf { it.firstOrNull()?.isDigit() == true }
    ?: "1.0.0"

val versionParts: Triple<Int, Int, Int> = appVersion.split(".").let { parts ->
    Triple(
        parts.getOrNull(0)?.toIntOrNull() ?: 1,
        parts.getOrNull(1)?.toIntOrNull() ?: 0,
        parts.getOrNull(2)?.toIntOrNull() ?: 0,
    )
}

android {
    namespace = "kz.qpvpn"
    compileSdk = 35

    defaultConfig {
        applicationId = "kz.qpvpn"
        minSdk = 26
        targetSdk = 35
        // Версию задаёт сборка: gradle assembleRelease -PqpvpnVersion=1.7.1.
        // Она же попадает в отчёт диагностики — иначе непонятно, что у
        // человека стоит.
        versionCode = versionParts.let { (major, minor, patch) -> major * 10_000 + minor * 100 + patch }
        versionName = appVersion
    }

    signingConfigs {
        create("sideload") {
            // Ключ лежит в репозитории осознанно: приложение ставится файлом,
            // а не через магазин. Он нужен только для того, чтобы обновления
            // вставали поверх прошлой версии, не стирая настройки.
            storeFile = file("qpvpn-sideload.jks")
            storePassword = "qpvpn-sideload"
            keyAlias = "qpvpn"
            keyPassword = "qpvpn-sideload"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("sideload")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            signingConfig = signingConfigs.getByName("sideload")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        // Нужен BuildConfig.VERSION_NAME: он показывается в диагностике.
        buildConfig = true
    }

    // Библиотеки туннеля занимали половину файла: они лежали внутри сразу
    // под четыре процессора, включая x86 и x86_64 — а это эмуляторы, не
    // телефоны. Оставляем только ARM.
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a")
            // Про запас — сборка, которая встанет на что угодно. Она вдвое
            // тяжелее, и по постоянной ссылке лежит не она.
            isUniversalApk = true
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    // Библиотека AmneziaWG: тот же WireGuard, но понимает параметры маскировки.
    // Собирается из исходников скриптом scripts/build-awg.sh.
    implementation(files("libs/awg-tunnel.aar"))
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("androidx.collection:collection:1.4.5")

    // Чтение QR-кодов без сервисов Google — они есть не на каждом телефоне.
    implementation("com.google.zxing:core:3.5.3")
    implementation("androidx.camera:camera-core:1.4.0")
    implementation("androidx.camera:camera-camera2:1.4.0")
    implementation("androidx.camera:camera-lifecycle:1.4.0")
    implementation("androidx.camera:camera-view:1.4.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")

    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
}
