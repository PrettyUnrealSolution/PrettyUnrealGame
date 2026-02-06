@echo off
powershell.exe -Command "if((Get-ExecutionPolicy ) -ne 'AllSigned') { Set-ExecutionPolicy -Scope Process Bypass }; &'%~dp0BuildObriy.ps1' %*"