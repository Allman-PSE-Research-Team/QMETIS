@ECHO OFF
IF NOT EXIST build\windows MKDIR build\windows
CD build\windows
cmake -DCMAKE_CONFIGURATION_TYPES="Release" ..\.. %*
IF ERRORLEVEL 1 EXIT /B %ERRORLEVEL%
ECHO VS files have been generated in build\windows
CD ..\..
