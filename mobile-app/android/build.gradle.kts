import org.gradle.api.file.Directory
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
    afterEvaluate {
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.apply {
            // Older plugins (e.g. edge_detection) predate AGP's namespace
            // requirement and don't declare one in their build.gradle. Fall
            // back to the `package` attribute in their own AndroidManifest.xml
            // so they still build under modern AGP without patching pub-cache.
            if (namespace == null) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val match = Regex("package=\"([^\"]+)\"").find(manifestFile.readText())
                    if (match != null) {
                        namespace = match.groupValues[1]
                    }
                }
            }
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
        // Fix: some androidx.camera releases don't transitively pull in
        // concurrent-futures, causing CallbackToFutureAdapter class-not-found
        // errors during compilation of camera_android_camerax.
        if (project.name == "camera_android_camerax") {
            dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}