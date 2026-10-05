# Export web + Windows builds and zip them for upload (Netlify / itch.io).
# Run from anywhere: powershell -File web\build_release.ps1
$g = "C:\Users\rew25\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
Set-Location (Split-Path $PSScriptRoot)
python web\build_shell.py
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force build\web, build\windows | Out-Null
New-Item -ItemType File build\.gdignore | Out-Null
& $g --headless --path . --export-release "Web" build/web/index.html 2>&1 | Select-String -Pattern "ERROR|WARNING"
& $g --headless --path . --export-release "Windows" build/windows/ElephantDuel.exe 2>&1 | Select-String -Pattern "ERROR|WARNING"
Copy-Item assets\fonts\*-OFL.txt build\windows\
Copy-Item assets\fonts\*-OFL.txt build\web\
Compress-Archive -Path build\web\* -DestinationPath build\ElephantDuel-web.zip -Force
Compress-Archive -Path build\windows\* -DestinationPath build\ElephantDuel-windows.zip -Force
Get-ChildItem build -File | Select-Object Name, @{n = "MB"; e = { [math]::Round($_.Length / 1MB, 1) } }
