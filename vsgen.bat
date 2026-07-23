MKDIR build\windows
MKDIR build\xinclude
COPY /Y include\metis.h build\xinclude
COPY /Y include\CMakeLists.txt build\xinclude
CD build\windows
cmake -DCMAKE_CONFIGURATION_TYPES="Release" ..\.. %*
ECHO VS files have been generated in build\windows
CD ..\..\
