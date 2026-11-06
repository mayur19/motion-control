plugins {
    id("com.android.application")
}

android {
    namespace = "com.motionbadminton.controller.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.motionbadminton.controller.android"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("com.google.code.gson:gson:2.12.0")
}
