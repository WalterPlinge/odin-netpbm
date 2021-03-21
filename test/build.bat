@echo off

set APP="test.exe"

call odin build . -out:%APP% -debug -show-timings -llvm-api -collection:image=..\

if exist %APP% (
	if "%1" == "-run" call %APP%
	if "%1" == "-r" call %APP%
)
