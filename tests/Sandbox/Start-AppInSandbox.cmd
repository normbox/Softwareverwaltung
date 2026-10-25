@echo off
rem Wird von Windows Sandbox beim Anmelden ueber explorer.exe gestartet, damit das Konsolenfenster sichtbar ist.
start "App-Test Softwareverwaltung" powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File C:\Repo\tests\Sandbox\Invoke-AppSandboxTest.ps1
