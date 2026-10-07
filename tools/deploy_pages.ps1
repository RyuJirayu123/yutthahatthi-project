# Put the web build on GitHub Pages: https://<user>.github.io/<repo>/
#
#   deploy.bat                  newest version in release\ (run publish.bat first)
#   deploy.bat -Version 2.1.0   a specific version (e.g. to roll back)
#
# The files go to the gh-pages branch of this repo, replacing what was there
# (only the latest build is kept, so the repo doesn't grow by ~40 MB per release).
# First time only: on GitHub open the repo > Settings > Pages >
# "Deploy from a branch" > branch gh-pages, folder / (root) > Save.
param([string]$Version = "")
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot)

if ($Version -eq "") {
	$latest = Get-ChildItem release -Directory -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -match '^v\d+\.\d+\.\d+$' } |
		Sort-Object { [version]$_.Name.Substring(1) } | Select-Object -Last 1
	if (-not $latest) { throw "No build in release\ - run publish.bat first" }
	$Version = $latest.Name.Substring(1)
}
$web = "release\v$Version\ElephantDuel-v$Version-web"
if (-not (Test-Path "$web\index.html")) { throw "$web not found - run publish.bat first" }

$remote = (git remote get-url origin).Trim()
$tmp = Join-Path ([IO.Path]::GetTempPath()) "elephant-duel-pages"
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory $tmp | Out-Null
Copy-Item "$web\*" $tmp -Recurse
New-Item -ItemType File "$tmp\.nojekyll" | Out-Null   # serve the files as they are

Write-Host "Uploading v$Version to GitHub Pages ..."
git -C $tmp init -q -b gh-pages
git -C $tmp add -A
git -C $tmp commit -q -m "Elephant Duel v$Version (web build)"
git -C $tmp push -f -q $remote gh-pages
if ($LASTEXITCODE) { throw "git push failed" }
Remove-Item -Recurse -Force $tmp

$m = [regex]::Match($remote, 'github\.com[/:]([^/]+)/([^/.]+)')
Write-Host ""
Write-Host "  v$Version uploaded." -ForegroundColor Green
if ($m.Success) {
	Write-Host "  Play: https://$($m.Groups[1].Value.ToLower()).github.io/$($m.Groups[2].Value)/  (live in about a minute)"
}
Write-Host ""
