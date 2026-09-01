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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// androidx libraries (lifecycle 2.7.x, core 1.13.x, ...) require every
// consuming module to compile against SDK 34 or newer, while plugin
// modules default to the Flutter template's android-33. Raise each
// Android module to 36 after its own build script has run. Done via the
// Groovy property bridge so it works with either AGP DSL generation.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { androidExt ->
            (androidExt as groovy.lang.GroovyObject).setProperty("compileSdk", 36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
