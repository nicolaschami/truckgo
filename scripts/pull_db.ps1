# Copies the app's SQLite database from the connected Android phone to
# db-snapshot\ in the project, to open with DB Browser for SQLite.
# Works with debug builds only (the ones "flutter run" installs).
#
# Run from the project folder:
#   powershell -ExecutionPolicy Bypass -File scripts\pull_db.ps1

$ErrorActionPreference = 'Stop'

$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$package = 'com.example.truckg'
$outDir = Join-Path $PSScriptRoot '..\db-snapshot'

if (-not (Test-Path $adb)) {
    Write-Host "adb not found at $adb" -ForegroundColor Red
    exit 1
}

$devices = & $adb devices | Select-String -Pattern "`tdevice$"
if (-not $devices) {
    Write-Host 'No phone connected. Plug it in (USB debugging on) and try again.' -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force $outDir | Out-Null
$outDir = (Resolve-Path $outDir).Path

# Clear the previous copy (close it in DB Browser first)
foreach ($file in 'truckgo.db', 'truckgo.db-wal', 'truckgo.db-shm') {
    $target = Join-Path $outDir $file
    if (-not (Test-Path $target)) { continue }
    try {
        Remove-Item $target
    } catch {
        Write-Host 'The old copy is still open (DB Browser?). Close it and run this again.' -ForegroundColor Red
        exit 1
    }
}

# Copy only the files that exist on the phone. cmd.exe keeps the bytes
# intact; PowerShell 5.1 '>' would corrupt the file.
# (the phone may list several names on one line, so split on spaces)
$onPhone = (& $adb exec-out run-as $package ls databases) -split '\s+'
foreach ($file in 'truckgo.db', 'truckgo.db-wal', 'truckgo.db-shm') {
    if ($onPhone -notcontains $file) { continue }
    $target = Join-Path $outDir $file
    cmd /c "`"$adb`" exec-out run-as $package cat databases/$file > `"$target`""
}

$db = Join-Path $outDir 'truckgo.db'
if (-not (Test-Path $db)) {
    Write-Host 'No database found. Run the app once and pick a truck first.' -ForegroundColor Yellow
    exit 1
}

Write-Host "Database copied to $db" -ForegroundColor Green
if (Test-Path (Join-Path $outDir 'truckgo.db-wal')) {
    Write-Host 'Open it with DB Browser for SQLite (keep the -wal file next to it).'
} else {
    Write-Host 'Open it with DB Browser for SQLite.'
}
