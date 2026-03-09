@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo    ТЕСТИРОВАНИЕ ПРОИЗВОДИТЕЛЬНОСТИ КЕША
echo ========================================
echo.

REM Проверка, что приложение доступно
echo Проверка доступности приложения...
curl -s -o nul -w "%%{http_code}" http://localhost:8080 > temp.txt
set /p status=<temp.txt
del temp.txt

if not "%status%"=="200" (
    echo [ERROR] Приложение недоступно (HTTP %status^)
    echo Запустите сначала setup-cache.bat
    pause
    exit /b 1
)

echo [OK] Приложение доступно
echo.

REM Очистка кеша Redis
echo 1. Очистка кеша Redis...
docker compose exec redis redis-cli flushall >nul 2>&1
if %errorlevel% equ 0 (
    echo [OK] Кеш очищен
) else (
    echo [WARN] Не удалось очистить кеш
)
echo.

REM Прогрев (первый запрос)
echo 2. Прогрев (первый запрос - без кеша)...
curl -s http://localhost:8080/helloDoc/users -o nul
timeout /t 2 >nul
echo [OK] Прогрев выполнен
echo.

echo 3. Серия запросов с измерением времени:
echo ----------------------------------------
echo.

set total_time=0
set requests=5

for /l %%i in (1,1,%requests%) do (
    echo Запрос %%i:
    
    REM Выполняем запрос и сохраняем время
    for /f "tokens=*" %%t in ('curl -s -w "%%{time_total}" -o nul http://localhost:8080/helloDoc/users') do set time=%%t
    
    REM Выводим время
    echo   Время: !time! сек
    
    REM Добавляем к общему времени (конвертируем в число для сложения)
    for /f "tokens=1,2 delims=." %%a in ("!time!") do (
        set /a time_ms=%%a*1000 + %%b
        set /a total_time_ms=!total_time_ms! + !time_ms!
    )
    
    echo.
)

REM Вычисляем среднее
set /a avg_time_ms=%total_time_ms%/%requests%
set /a avg_sec=%avg_time_ms%/1000
set /a avg_ms=%avg_time_ms% %% 1000

echo ----------------------------------------
echo Среднее время: %avg_sec%.%avg_ms% сек
echo.

echo 4. Проверка заголовков ответа:
echo ----------------------------------------
curl -I http://localhost:8080/helloDoc/users 2>nul | findstr /i "X-Cache X-Query-Time"
if errorlevel 1 (
    echo [WARN] Заголовки кеша не найдены
)
echo.

echo 5. Статистика Redis:
echo ----------------------------------------
docker compose exec redis redis-cli info stats | findstr "keyspace_hits keyspace_misses"
docker compose exec redis redis-cli info keyspace
echo.

echo 6. Ключи в Redis:
echo ----------------------------------------
docker compose exec redis redis-cli --scan --pattern "users:*" || echo Ключи не найдены
echo.

echo ========================================
echo    ТЕСТИРОВАНИЕ ЗАВЕРШЕНО
echo ========================================
pause