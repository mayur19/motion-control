# Android motion controller

Native Kotlin controller shell with the same five states as iOS, build/device
diagnostics, declared camera/network/sensor/wake-lock requirements and a
session-scoped screen-awake policy.

## Build and test

```sh
cd apps/controller-android
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=$HOME/Library/Android/sdk
./gradlew testDebugUnitTest assembleDebug
```

AGP 9.2.1 supplies built-in Kotlin; do not apply `kotlin-android` separately.
The debug APK is written under `app/build/outputs/apk/debug/` and is ignored by
Git.
