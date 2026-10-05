@echo off
rem Double-click to build the release files. See tools\publish.ps1 for options.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\publish.ps1" %*
if "%~1"=="" pause
