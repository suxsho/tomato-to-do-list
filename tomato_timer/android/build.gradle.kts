allprojects {
    repositories {
        // 国内镜像优先（阿里云），官方源兜底
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://maven.aliyun.com/repository/gradle-plugin")
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
// 部分插件（如 file_picker 8.x）自带较低的 compileSdk，会被新依赖的
// AAR metadata 校验拦下；统一提升到 36 与主工程一致（反射实现，兼容新旧 DSL）
// 注意：必须在 evaluationDependsOn 之前注册 afterEvaluate
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        val current: Int = runCatching {
            androidExt.javaClass.getMethod("getCompileSdkVersion").invoke(androidExt) as? Int
        }.getOrNull()
            ?: runCatching { androidExt.javaClass.getMethod("getCompileSdk").invoke(androidExt) as? Int }.getOrNull()
            ?: 0
        if (current < 36) {
            runCatching {
                androidExt.javaClass.methods
                    .firstOrNull { it.name == "compileSdkVersion" && it.parameterTypes.firstOrNull() == Integer.TYPE }
                    ?.invoke(androidExt, 36)
                    ?: androidExt.javaClass.methods
                        .firstOrNull { it.name == "setCompileSdk" && it.parameterTypes.firstOrNull() == Integer.TYPE }
                        ?.invoke(androidExt, 36)
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
