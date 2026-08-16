import com.android.build.gradle.LibraryExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // file_picker 11 skips its Kotlin plugin on AGP 9 because it assumes
    // built-in Kotlin. This app temporarily disables built-in Kotlin for older
    // transitive plugins, so explicitly compile file_picker's Kotlin sources.
    if (name == "file_picker") {
        pluginManager.apply("org.jetbrains.kotlin.android")
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

// Reown pulls in coinbase_wallet_sdk, which ships with compileSdk 31 and missing
// consumer-rules.pro / proguard-rules.pro — patch all Android library plugins
// before tasks run.
subprojects {
    afterEvaluate {
        plugins.withId("com.android.library") {
            extensions.configure<LibraryExtension>("android") {
                compileSdk = 36
            }
        }
        if (name == "coinbase_wallet_sdk") {
            val consumer = file("consumer-rules.pro")
            if (!consumer.exists()) {
                consumer.writeText("# placeholder — coinbase_wallet_sdk omits this file\n")
            }
            val proguard = file("proguard-rules.pro")
            if (!proguard.exists()) {
                proguard.writeText("# placeholder — coinbase_wallet_sdk omits this file\n")
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
