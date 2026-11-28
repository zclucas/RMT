@echo off
call "%ProgramFiles(x86)%\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d "%~dp0"
cl /nologo /utf-8 /O2 /W3 /DUNICODE /D_UNICODE /D_CRT_SECURE_NO_WARNINGS L2dHost.c /Fe:L2dHost.exe /link /SUBSYSTEM:WINDOWS user32.lib gdi32.lib kernel32.lib
