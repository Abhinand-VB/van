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

// Flutter plugins inherit the Flutter default compileSdk, which is 37 on this
// Flutter version. The SDK manager installs that platform as "android-37.0"
// while Gradle looks it up as "android-37", so any module following the
// default fails to resolve. Force every Android module onto the installed 36.
//
// This runs from plugins.withId rather than afterEvaluate because the
// evaluationDependsOn below has already evaluated these projects by then.
subprojects {
    val pinCompileSdk = Action<Any> {
        val android = extensions.findByName("android") ?: return@Action
        android.javaClass.methods
            .firstOrNull {
                it.name == "setCompileSdkVersion" &&
                    it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] == Int::class.javaPrimitiveType
            }
            ?.invoke(android, 36)
    }
    plugins.withId("com.android.library") { pinCompileSdk.execute(this) }
    plugins.withId("com.android.application") { pinCompileSdk.execute(this) }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
