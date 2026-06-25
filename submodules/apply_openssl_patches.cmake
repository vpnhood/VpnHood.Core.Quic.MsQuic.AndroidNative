# apply_openssl_patches.cmake
# Run as: cmake -DOPENSSL_SRC=<dir> -DPATCH_FILE=<patch> -P apply_openssl_patches.cmake
#
# Applies a patch to the OpenSSL submodule source tree on the build host.
#
# Rationale: some fixes (e.g. Windows-host build tweaks to Configurations/15-android.conf)
# cannot be committed into the upstream OpenSSL submodule, which only records a commit
# pointer. Instead they live as patches under submodules/patches/ and are applied to the
# submodule working tree at configure time.
#
# Idempotent: if the patch already reverse-applies cleanly, it is already in the tree and
# the step is skipped. Safe to re-run.

cmake_minimum_required(VERSION 3.10)

if(NOT OPENSSL_SRC OR NOT PATCH_FILE)
    message(FATAL_ERROR "OPENSSL_SRC and PATCH_FILE must both be set")
endif()

find_program(GIT_EXECUTABLE git REQUIRED)

# If the patch reverse-applies cleanly, it is already present — nothing to do.
execute_process(
    COMMAND ${GIT_EXECUTABLE} apply --reverse --check "${PATCH_FILE}"
    WORKING_DIRECTORY "${OPENSSL_SRC}"
    RESULT_VARIABLE already_applied
    OUTPUT_QUIET ERROR_QUIET
)
if(already_applied EQUAL 0)
    message(STATUS "OpenSSL patch already applied: ${PATCH_FILE}")
    return()
endif()

execute_process(
    COMMAND ${GIT_EXECUTABLE} apply "${PATCH_FILE}"
    WORKING_DIRECTORY "${OPENSSL_SRC}"
    RESULT_VARIABLE apply_result
    ERROR_VARIABLE apply_error
)
if(NOT apply_result EQUAL 0)
    message(FATAL_ERROR "Failed to apply OpenSSL patch ${PATCH_FILE}:\n${apply_error}")
endif()
message(STATUS "Applied OpenSSL patch: ${PATCH_FILE}")
