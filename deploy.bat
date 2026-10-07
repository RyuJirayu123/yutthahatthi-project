@echo off
rem Double-click to put the newest web build on GitHub Pages. See tools\deploy_pages.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\deploy_pages.ps1" %*
if "%~1"=="" pause
