plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    `maven-publish`
}

/// One version for both platforms: the release workflow tags on a
/// `MARKETING_VERSION` bump, so reading it here is what keeps the published
/// Android artifact and the tag that triggered it in step. The fallback is for
/// a checkout of this module on its own, without the Xcode project beside it.
val libraryVersion: String = run {
    val config = rootDir.parentFile?.resolve("Local_Response_Mapper/Config.xcconfig")
    val fromConfig = config?.takeIf { it.isFile }
        ?.readLines()
        ?.firstOrNull { it.trimStart().startsWith("MARKETING_VERSION") }
        ?.substringAfter("=")
        ?.trim()
        ?.trimEnd(';')
    (project.findProperty("libraryVersion") as String?) ?: fromConfig ?: "0.0.0-SNAPSHOT"
}

android {
    namespace = "com.chanonly123.local_response"
    compileSdk = 36

    defaultConfig {
        minSdk = 24

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

dependencies {

    // `api`, not `implementation`: the library's whole public surface is an
    // OkHttp `Interceptor`, so a consumer cannot use it without OkHttp on the
    // compile classpath.
    api(libs.okhttp)

    // Internal only — the wire format with the mapper. Nothing in the public
    // API mentions Gson.
    implementation(libs.gson)

    // Used directly for the fire-and-forget record calls. It arrived
    // transitively through appcompat before; declared here so dropping a UI
    // dependency cannot take it away.
    implementation(libs.kotlinx.coroutines.android)

//    testImplementation(libs.junit)
//    androidTestImplementation(libs.androidx.junit)
//    androidTestImplementation(libs.androidx.espresso.core)
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = "com.chanonly123"
            artifactId = "local-response"
            version = libraryVersion

            // The release component only exists once AGP has created the
            // variants, which happens after this block is evaluated.
            afterEvaluate {
                from(components["release"])
            }

            pom {
                name.set("Local Response")
                description.set(
                    "OkHttp interceptor that records traffic to the Local Response " +
                        "Mapper and serves mapped responses from it."
                )
                url.set("https://github.com/chanonly123/local-response")
                licenses {
                    license {
                        name.set("MIT License")
                        url.set("https://github.com/chanonly123/local-response/blob/main/LICENSE")
                    }
                }
                developers {
                    developer {
                        id.set("chanonly123")
                        name.set("Chandan Karmakar")
                    }
                }
                scm {
                    url.set("https://github.com/chanonly123/local-response")
                    connection.set("scm:git:https://github.com/chanonly123/local-response.git")
                    developerConnection.set("scm:git:ssh://git@github.com/chanonly123/local-response.git")
                }
            }
        }
    }
}
