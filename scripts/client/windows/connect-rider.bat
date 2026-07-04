@echo off
title Claude Connect (Rider)
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0connect.ps1" -Ide cursor %*
