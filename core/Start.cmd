ECHO Starting custom deployment script

REM Switch CWD to same directory as batch file
cd /d %~dp0

PowerShell.exe -ExecutionPolicy Unrestricted .\Start.ps1 >> ".\Start.log" 2>&1

EXIT /B %ERRORLEVEL%