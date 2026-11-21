@echo off
rem Wird von Windows Sandbox beim Anmelden ueber explorer.exe gestartet, damit das Konsolenfenster sichtbar ist.
start "Sandbox-Pruefung rd und Junctions" powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File C:\Repo\tests\Sandbox\Test-RdJunction.ps1
