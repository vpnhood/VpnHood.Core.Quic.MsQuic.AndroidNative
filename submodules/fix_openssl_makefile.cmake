# fix_openssl_makefile.cmake
# Run as: cmake -P fix_openssl_makefile.cmake -DMAKEFILE_PATH=...
# Replaces backslash path separators in the OpenSSL Makefile with forward
# slashes so that GNU make with SHELL=sh.exe can process them without
# interpreting backslashes as escape characters.

cmake_minimum_required(VERSION 3.10)

if(NOT MAKEFILE_PATH)
    message(FATAL_ERROR "MAKEFILE_PATH not set")
endif()

file(READ "${MAKEFILE_PATH}" content)

# Replace backslash followed by any letter/digit/dot/underscore with /
# Use a CMake regex which doesn't have shell-quoting issues.
# Note: We use [A-Za-z0-9_.] to match path chars, avoiding replacing
# line-continuation backslashes (followed by newline) and rule backslashes.
string(REGEX REPLACE "\\\\([A-Za-z0-9_.])" "/\\1" content "${content}")

file(WRITE "${MAKEFILE_PATH}" "${content}")

message(STATUS "Patched ${MAKEFILE_PATH}")
