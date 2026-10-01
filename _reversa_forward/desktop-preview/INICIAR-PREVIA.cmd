@echo off
title MistakeMap - Previa local
cd /d "D:\MistakeMap\appmistakemap"
echo A previa estara disponivel em http://localhost:8765/
echo Mantenha esta janela aberta enquanto usa a previa.
echo.
call "C:\src\flutter\bin\flutter.bat" run -d web-server --web-hostname 127.0.0.1 --web-port 8765 --no-pub
echo.
echo O servidor de previa foi encerrado.
pause
