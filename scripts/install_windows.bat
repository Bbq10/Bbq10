@echo off
setlocal EnableExtensions
REM Copy DerivGoldStepEA.mq5 into every MT5 Experts folder on this Windows user profile.
REM Run this on the PC / VPS that hosts MetaTrader 5, then compile in MetaEditor (F7).

set "SRC=%~dp0..\MQL5\Experts\DerivGoldStepEA.mq5"
if not exist "%SRC%" (
  echo Cannot find %SRC%
  exit /b 1
)

set "FOUND=0"
for /d %%D in ("%APPDATA%\MetaQuotes\Terminal\*") do (
  if exist "%%D\MQL5\Experts" (
    copy /Y "%SRC%" "%%D\MQL5\Experts\DerivGoldStepEA.mq5" >nul
    echo Installed to %%D\MQL5\Experts\
    set "FOUND=1"
  )
)

if "%FOUND%"=="0" (
  echo No MetaTrader 5 data folder found under %%APPDATA%%\MetaQuotes\Terminal
  echo Open MT5, then File - Open Data Folder, and copy MQL5\Experts\DerivGoldStepEA.mq5 yourself.
  exit /b 2
)

echo.
echo Done. Restart MT5, open MetaEditor, compile DerivGoldStepEA.mq5 with F7.
echo Then drag it onto an XAUUSD or Step Index chart and turn Algo Trading GREEN.
endlocal
