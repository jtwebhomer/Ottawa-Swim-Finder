# Patches objectbox_flutter_libs compileSdk for Android Gradle Plugin 9 compatibility.
# Run after `flutter pub get` if Android builds fail on AAR metadata checks.

$pubCache = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev"
$matches = Get-ChildItem -Path $pubCache -Filter "objectbox_flutter_libs-*" -Directory -ErrorAction SilentlyContinue

if (-not $matches) {
    Write-Host "objectbox_flutter_libs not found in pub cache; skipping patch."
    exit 0
}

foreach ($dir in $matches) {
    $buildGradle = Join-Path $dir.FullName "android\build.gradle"
    if (-not (Test-Path $buildGradle)) { continue }

    $content = Get-Content $buildGradle -Raw
    if ($content -match 'compileSdkVersion 36') {
        Write-Host "Already patched: $($dir.Name)"
        continue
    }

    $updated = $content -replace 'compileSdkVersion\s+\d+', 'compileSdkVersion 36'
    Set-Content -Path $buildGradle -Value $updated -NoNewline
    Write-Host "Patched compileSdk to 36: $($dir.Name)"
}
