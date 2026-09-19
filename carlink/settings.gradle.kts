pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "CarLink"

// Протокол общий для обеих сторон провода: телефон и эмулятор головного
// устройства собираются из одного и того же кода.
include(":core")
include(":app")
include(":headunit")
