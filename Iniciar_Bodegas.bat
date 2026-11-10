@echo off
setlocal

set "INICIADOR=%~dp0scripts\iniciar_bodegas.ps1"
if not exist "%INICIADOR%" (
    echo No se encontro scripts\iniciar_bodegas.ps1.
    echo Comprueba que este archivo permanezca en la raiz del proyecto.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%INICIADOR%"
set "RESULTADO=%ERRORLEVEL%"
echo.
pause
exit /b %RESULTADO%
