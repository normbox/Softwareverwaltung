@echo off
rem Wird von Windows Sandbox beim Anmelden ueber explorer.exe gestartet, damit das Konsolenfenster sichtbar ist.
start "Sandbox-Test Softwareverwaltung" powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File C:\Repo\tests\Sandbox\Invoke-ActionSandboxTest.ps1
