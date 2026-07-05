@echo off
:: .env dosyasından değerleri oku
for /f "tokens=1,2 delims==" %%A in ('findstr "NGROK_" .env') do (
    set "%%A=%%B"
)

:: Tırnakları temizle
set NGROK_AUTHTOKEN=%NGROK_AUTHTOKEN:"=%
set NGROK_DOMAIN=%NGROK_DOMAIN:"=%

if "%NGROK_AUTHTOKEN%"=="" (
    echo HATA: .env dosyasinda NGROK_AUTHTOKEN eksik!
    pause
    exit /b 1
)

if "%NGROK_DOMAIN%"=="" (
    echo HATA: .env dosyasinda NGROK_DOMAIN eksik!
    pause
    exit /b 1
)

echo Auth token ayarlaniyor...
ngrok config add-authtoken %NGROK_AUTHTOKEN%

echo.
echo Tunnel baslatiliyor: %NGROK_DOMAIN% -> localhost:11434
echo AkyuzIDE Remote Host: https://%NGROK_DOMAIN%
echo.
ngrok http --domain=%NGROK_DOMAIN% 11434
