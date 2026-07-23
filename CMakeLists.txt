cmake_minimum_required(VERSION 3.10)
project(QMETIS C)

include(GNUInstallDirs)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# T3.1: enable link-time / interprocedural optimization when the toolchain
# supports it. Lets the hot k-way/FM refinement loops inline the rpq* priority
# queue ops (instantiated in libmetis/gklib.c) across translation units.
include(CheckIPOSupported)
check_ipo_supported(RESULT METIS_IPO_SUPPORTED OUTPUT METIS_IPO_MSG)
if(METIS_IPO_SUPPORTED)
  set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)
  message(STATUS "QMETIS: interprocedural optimization (LTO) enabled")
else()
  message(STATUS "QMETIS: IPO/LTO not supported: ${METIS_IPO_MSG}")
endif()
option(SHARED "build shared libraries" OFF)
option(METIS_INSTALL "install QMETIS libraries, headers, and programs" ON)
if(MSVC)
  set(QMETIS_BUILD_PROGRAMS_DEFAULT OFF)
else()
  set(QMETIS_BUILD_PROGRAMS_DEFAULT ON)
endif()
option(QMETIS_BUILD_PROGRAMS "build QMETIS command-line programs"
  ${QMETIS_BUILD_PROGRAMS_DEFAULT})
unset(QMETIS_BUILD_PROGRAMS_DEFAULT)
set(IDXTYPEWIDTH "32" CACHE STRING "width of idx_t (32 or 64)")
set(REALTYPEWIDTH "32" CACHE STRING "width of real_t (32 or 64)")
set_property(CACHE IDXTYPEWIDTH PROPERTY STRINGS 32 64)
set_property(CACHE REALTYPEWIDTH PROPERTY STRINGS 32 64)

if(NOT IDXTYPEWIDTH MATCHES "^(32|64)$")
  message(FATAL_ERROR "IDXTYPEWIDTH must be 32 or 64")
endif()
if(NOT REALTYPEWIDTH MATCHES "^(32|64)$")
  message(FATAL_ERROR "REALTYPEWIDTH must be 32 or 64")
endif()

set(QMETIS_GENERATED_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/include")
file(MAKE_DIRECTORY "${QMETIS_GENERATED_INCLUDE_DIR}")
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/include/metis.h" QMETIS_PUBLIC_HEADER)
file(WRITE "${QMETIS_GENERATED_INCLUDE_DIR}/metis.h"
  "#define IDXTYPEWIDTH ${IDXTYPEWIDTH}\n"
  "#define REALTYPEWIDTH ${REALTYPEWIDTH}\n"
  "${QMETIS_PUBLIC_HEADER}")
unset(QMETIS_PUBLIC_HEADER)
message(STATUS "QMETIS ABI: IDXTYPEWIDTH=${IDXTYPEWIDTH}, REALTYPEWIDTH=${REALTYPEWIDTH}")

# Configure QMETIS library artifacts.
if(SHARED)
  set(METIS_LIBRARY_TYPE SHARED)
else()
  set(METIS_LIBRARY_TYPE STATIC)
endif(SHARED)

include(./conf/gkbuild.cmake)

# QMETIS' custom options
#option(IDX64 "enable 64 bit ints" OFF)
#option(REAL64 "enable 64 bit floats (i.e., double)" OFF)
#if(IDX64)
#  set(METIS_COPTIONS "${METIS_COPTIONS} -DIDXTYPEWIDTH=64")
#else()
#  set(METIS_COPTIONS "${METIS_COPTIONS} -DIDXTYPEWIDTH=32")
#endif(IDX64)
#if(REAL64)
#  set(METIS_COPTIONS "${METIS_COPTIONS} -DREALTYPEWIDTH=64")
#else()
#  set(METIS_COPTIONS "${METIS_COPTIONS} -DREALTYPEWIDTH=32")
#endif(REAL64)
#
#set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${METIS_COPTIONS}")


# Add include directories.
# i.e., the -I equivalent
include_directories(BEFORE ${QMETIS_GENERATED_INCLUDE_DIR})
include_directories(${GKLIB_PATH}/include)
include_directories(${CMAKE_INSTALL_PREFIX}/include)

# List of paths that the compiler will search for library files.
# i.e., the -L equivalent
set(METIS_LINK_DIRS)
foreach(prefix ${GKLIB_PATH} ${CMAKE_INSTALL_PREFIX})
  foreach(libdir ${CMAKE_INSTALL_LIBDIR} lib64 lib)
    if(IS_DIRECTORY "${prefix}/${libdir}")
      list(APPEND METIS_LINK_DIRS "${prefix}/${libdir}")
    endif()
  endforeach()
endforeach()
list(REMOVE_DUPLICATES METIS_LINK_DIRS)
link_directories(${METIS_LINK_DIRS})

# Recursively look for CMakeLists.txt in subdirs.
add_subdirectory("libmetis")
if(QMETIS_BUILD_PROGRAMS)
  add_subdirectory("programs")
endif()

if(METIS_INSTALL)
  install(FILES "${QMETIS_GENERATED_INCLUDE_DIR}/metis.h"
    DESTINATION include RENAME qmetis.h)
  install(FILES "${QMETIS_GENERATED_INCLUDE_DIR}/metis.h"
    DESTINATION include)
endif()
