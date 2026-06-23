# Prepare Ottawa Swim Finder for Android Studio + Flutter debugging.
# Run from repo root: .\scripts\setup_android_studio.ps1

$ErrorActionPreference = "Stop"

$flutterBin = "E:\flutter\bin"
if (-not (Test-Path "$flutterBin\flutter.bat")) {
    Write-Error "Flutter SDK not found at E:\flutter. Update `$flutterBin in this script."
}
$env:Path = "$flutterBin;" + $env:Path

$appDir = Join-Path $PSScriptRoot "..\app" | Resolve-Path
Set-Location $appDir

Write-Host "==> flutter pub get"
flutter pub get

Write-Host "==> Patch Android plugin compatibility"
& (Join-Path $PSScriptRoot "patch_objectbox.ps1")

Write-Host "==> Regenerate IDE / platform files"
flutter create . --project-name ottawa_swim_finder --org ca.ottawa --platforms=android

Write-Host "==> Ensure local.properties"
$localProps = Join-Path $appDir "android\local.properties"
$props = @"
sdk.dir=C:\\Users\\Jtcra\\AppData\\Local\\Android\\sdk
flutter.sdk=E:\\flutter
flutter.versionName=1.0.0
flutter.versionCode=1
"@
Set-Content -Path $localProps -Value $props

Write-Host "==> flutter doctor"
flutter doctor

Write-Host "==> Verify debug build"
flutter build apk --debug

Write-Host ""
Write-Host "Ready for Android Studio."
Write-Host "Open this folder as the project root:"
Write-Host "  $appDir"
Write-Host ""
Write-Host "In Android Studio:"
Write-Host "  1. File -> Open -> select the app folder above"
Write-Host "  2. Install Flutter + Dart plugins if prompted"
Write-Host "  3. File -> Settings -> Languages & Frameworks -> Flutter"
Write-Host "     Set Flutter SDK path to: E:\flutter"
Write-Host "  4. Select a device/emulator, choose 'main.dart (debug)', click Run"
