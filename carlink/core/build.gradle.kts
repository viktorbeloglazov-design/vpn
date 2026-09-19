plugins {
    id("org.jetbrains.kotlin.jvm")
}

// Версию байт-кода задаём явно, а не через toolchain: собирать ядро можно любой
// Java, а приложению Android нужен уровень 17.
java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.release.set(17)
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
