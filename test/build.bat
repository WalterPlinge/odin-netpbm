@echo off

set APP="test.exe"

call odin build . -out:%APP% -show-timings -debug -vet

if exist %APP% (
	if "%1" == "-run" call %APP%
	if "%1" == "-r" call %APP%
)
