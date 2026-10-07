# Build every release file for one version of Elephant Duel.
#
# The version lives in ONE place: application/config/version in project.godot
# (Godot: Project Settings > Application > Config > Version). The game, the web
# loading page, the Windows .exe details and the file names all read it from there.
#
#   publish.bat                 asks which version to build
#   publish.bat -Bump patch     1.1.0 -> 1.1.1  bug fixes
#   publish.bat -Bump minor     1.1.0 -> 1.2.0  new features
#   publish.bat -Bump major     1.1.0 -> 2.0.0  big changes
#   publish.bat -Bump none      rebuild the current version
#   publish.bat -Version 1.4.2  set an exact version
#
# Output: release\v<version>\
#   ElephantDuel-v<version>-web\         put online with deploy.bat (GitHub Pages)
#   ElephantDuel-v<version>-web.zip      upload to itch.io (HTML game)
#   ElephantDuel-v<version>-windows.zip  download for Windows
param(
	[ValidateSet("", "none", "patch", "minor", "major")][string]$Bump = "",
	[string]$Version = ""
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # no zip progress bar
$godot = "C:\Users\rew25\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
Set-Location (Split-Path $PSScriptRoot)
$utf8 = New-Object System.Text.UTF8Encoding $false

# ---------- version ----------
$proj = [IO.File]::ReadAllText("$PWD\project.godot")
$m = [regex]::Match($proj, 'config/version="(\d+)\.(\d+)\.(\d+)"')
if (-not $m.Success) { throw "project.godot has no config/version=""x.y.z""" }
$maj = [int]$m.Groups[1].Value; $min = [int]$m.Groups[2].Value; $pat = [int]$m.Groups[3].Value
$current = "$maj.$min.$pat"
$next = @{ none = $current; patch = "$maj.$min.$($pat + 1)"; minor = "$maj.$($min + 1).0"; major = "$($maj + 1).0.0" }

if ($Version -eq "" -and $Bump -eq "") {
	Write-Host ""
	Write-Host "  Elephant Duel - current version $current" -ForegroundColor Yellow
	Write-Host "  [Enter] rebuild $current"
	Write-Host "  [1] patch -> $($next.patch)   bug fixes / small tweaks"
	Write-Host "  [2] minor -> $($next.minor)   new features"
	Write-Host "  [3] major -> $($next.major)   big update"
	$pick = Read-Host "  Choose"
	$Bump = @{ "" = "none"; "1" = "patch"; "2" = "minor"; "3" = "major" }[$pick.Trim()]
	if (-not $Bump) { throw "Unknown choice '$pick'" }
}
if ($Version -eq "") { $Version = $next[$Bump] }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 1.2.3, got '$Version'" }
if ($Version -ne $current) {
	$proj = $proj.Remove($m.Index, $m.Length).Insert($m.Index, "config/version=""$Version""")
	[IO.File]::WriteAllText("$PWD\project.godot", $proj, $utf8)
	Write-Host "Version $current -> $Version (project.godot)" -ForegroundColor Green
}

# ---------- build ----------
$name = "ElephantDuel-v$Version"
$out = "release\v$Version"
$web = "$out\$name-web"
$win = "$out\windows"
python web\build_shell.py
if ($LASTEXITCODE) { throw "build_shell.py failed" }
New-Item -ItemType Directory -Force release | Out-Null
if (-not (Test-Path release\.gdignore)) { New-Item -ItemType File release\.gdignore | Out-Null }
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $web, $win | Out-Null

function Export([string]$preset, [string]$path) {
	Write-Host "Exporting $preset ..."
	$log = & $godot --headless --path . --export-release $preset $path 2>&1 | Out-String
	if (-not (Test-Path $path)) { Write-Host $log; throw "$preset export failed" }
	$log -split "`n" | Select-String -Pattern "ERROR" | ForEach-Object { Write-Host $_ -ForegroundColor Red }
}
Export "Web" "$web/index.html"
Export "Windows" "$win/ElephantDuel.exe"
Copy-Item assets\fonts\*-OFL.txt $web
Copy-Item assets\fonts\*-OFL.txt $win
Compress-Archive -Path "$web\*" -DestinationPath "$out\$name-web.zip" -Force
Compress-Archive -Path "$win\*" -DestinationPath "$out\$name-windows.zip" -Force
Remove-Item -Recurse -Force $win

# ---------- summary ----------
Write-Host ""
Write-Host "  Elephant Duel v$Version is ready in $out" -ForegroundColor Green
Get-ChildItem $out | ForEach-Object {
	$size = if ($_.PSIsContainer) { (Get-ChildItem $_.FullName -Recurse -File | Measure-Object Length -Sum).Sum } else { $_.Length }
	"    {0,-36} {1,6:N1} MB" -f $_.Name, ($size / 1MB)
}
Write-Host ""
Write-Host "  Web     : double-click deploy.bat to put it on GitHub Pages"
Write-Host "  itch.io : upload $name-web.zip (played in the browser) + $name-windows.zip"
Write-Host "  GitHub  : git commit -am ""v$Version"" ; git tag v$Version ; git push --follow-tags"
Write-Host ""
if ($PSBoundParameters.Count -eq 0) { explorer.exe $out }   # opened by double-click: show the files
