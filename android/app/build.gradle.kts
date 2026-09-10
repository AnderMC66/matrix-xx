import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La firma de release vive fuera del repo: `android/key.properties` apunta al
// almacén de claves y trae sus contraseñas, y está en .gitignore. Sin ese
// archivo el build de release sigue funcionando —firmado con la clave de
// depuración, como hasta ahora— para que `flutter run --release` no exija
// montar un keystore. Lo que NO se puede es publicar así: Play rechaza un APK
// firmado con la clave de debug, y aunque no lo hiciera, esa clave es la misma
// en todas las máquinas del mundo, así que cualquiera podría firmar una
// actualización de esta app. Ver LEEME.md, «Firmar el APK de release».
val propiedadesFirma = Properties()
val archivoFirma = rootProject.file("key.properties")
if (archivoFirma.exists()) {
    archivoFirma.inputStream().use { propiedadesFirma.load(it) }
}
val hayFirmaPropia = propiedadesFirma.containsKey("storeFile")

// Que no pase en silencio: un APK de release firmado con la clave de debug se
// instala y se ve perfecto, así que el fallo solo aparece al intentar subirlo.
if (!hayFirmaPropia) {
    gradle.taskGraph.whenReady {
        if (allTasks.any { it.name.contains("Release") }) {
            logger.warn(
                "AVISO: android/key.properties no existe, así que este build de " +
                    "release va firmado con la clave de DEPURACIÓN. Sirve para " +
                    "probar; Play lo rechaza. Ver LEEME.md, «Firmar el APK de release»."
            )
        }
    }
}

android {
    namespace = "com.ander_u.matr_u"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Este identificador es definitivo: una vez publicado en Play no se
        // puede cambiar sin que sea otra app distinta, que perdería a todos
        // los instalados.
        applicationId = "com.ander_u.matr_u"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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
        if (hayFirmaPropia) {
            create("release") {
                storeFile = file(propiedadesFirma.getProperty("storeFile"))
                storePassword = propiedadesFirma.getProperty("storePassword")
                keyAlias = propiedadesFirma.getProperty("keyAlias")
                keyPassword = propiedadesFirma.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hayFirmaPropia) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
