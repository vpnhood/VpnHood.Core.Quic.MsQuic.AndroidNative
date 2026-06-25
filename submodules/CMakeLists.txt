# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

cmake_minimum_required(VERSION 3.16)

# This is a helper project to build OpenSSL as part of the CMake "superbuild"
# pattern, which sidesteps issues managing a dependency graph within a single
# CMake project and enables smoother developer workflows.

# This file is intended to be included in the parent msquic project via FetchContent
project(OpenSSLQuic)

set(QUIC_BUILD_DIR ${CMAKE_CURRENT_BINARY_DIR})
option(QUIC_USE_SYSTEM_LIBCRYPTO "Use system libcrypto if quictls TLS" OFF)

if(QUIC_TLS_LIB STREQUAL "quictls" OR QUIC_TLS_LIB STREQUAL "openssl")
    message(STATUS "Configuring for OpenSSL 3.x")
    set(EXPECTED_OPENSSL_VERSION 3.0)
    if(QUIC_TLS_LIB STREQUAL "quictls")
        set(QUIC_OPENSSL quictls)
    else()
        set(QUIC_OPENSSL openssl)
    endif()
else()
    message(FATAL_ERROR "Unsupported QUIC_TLS_LIB ${QUIC_TLS_LIB}")
endif()

set(OPENSSL_DIR ${QUIC_BUILD_DIR}/${QUIC_OPENSSL})

set(OPENSSL_CONFIG_FLAGS
    enable-tls1_3 no-makedepend no-dgram no-ssl3 no-psk no-srp

    no-zlib no-egd no-idea no-rc5 no-rc4 no-afalgeng
    no-comp no-cms no-ct no-srp no-srtp no-ts no-gost no-dso no-ec2m
    no-tls1 no-tls1_1 no-tls1_2 no-dtls no-dtls1 no-dtls1_2 no-ssl
    no-ssl3-method no-tls1-method no-tls1_1-method no-tls1_2-method no-dtls1-method no-dtls1_2-method
    no-siphash no-whirlpool no-aria no-bf no-blake2 no-sm2 no-sm3 no-sm4 no-camellia no-cast no-md4 no-mdc2 no-ocb no-rc2 no-rmd160 no-scrypt no-seed
    no-weak-ssl-ciphers no-shared no-tests
    no-uplink no-cmp no-fips no-padlockeng no-siv no-legacy no-dtls no-deprecated --libdir=lib)

if (WIN32)

    if (DEFINED ENV{CommonProgramFiles})
        message(STATUS "Setting openssldir to $ENV{CommonProgramFiles}\\SSL")
        list(APPEND OPENSSL_CONFIG_FLAGS --openssldir=\"$ENV{CommonProgramFiles}\\SSL\")
    endif()

    set(LIBSSL_DEBUG_PATH ${OPENSSL_DIR}/debug/lib/libssl${CMAKE_STATIC_LIBRARY_SUFFIX})
    set(LIBCRYPTO_DEBUG_PATH ${OPENSSL_DIR}/debug/lib/libcrypto${CMAKE_STATIC_LIBRARY_SUFFIX})
    set(LIBSSL_PATH ${OPENSSL_DIR}/release/lib/libssl${CMAKE_STATIC_LIBRARY_SUFFIX})
    set(LIBCRYPTO_PATH ${OPENSSL_DIR}/release/lib/libcrypto${CMAKE_STATIC_LIBRARY_SUFFIX})

    if (QUIC_UWP_BUILD)
        # Translate target architecture into corresponding OpenSSL build flag
        if (${SYSTEM_PROCESSOR} STREQUAL "arm64")
            set(QUIC_OPENSSL_WIN_ARCH "VC-WIN64-ARM")
        elseif (${SYSTEM_PROCESSOR} STREQUAL "arm")
            set(QUIC_OPENSSL_WIN_ARCH "VC-WIN32-ARM")
        elseif (${SYSTEM_PROCESSOR} STREQUAL "win32" OR ${SYSTEM_PROCESSOR} STREQUAL "x86")
            set(QUIC_OPENSSL_WIN_ARCH "VC-WIN32-ONECORE")
        elseif (${SYSTEM_PROCESSOR} STREQUAL "x64" OR ${SYSTEM_PROCESSOR} STREQUAL "amd64")
            set(QUIC_OPENSSL_WIN_ARCH "VC-WIN64A-ONECORE")
        else()
            message(FATAL_ERROR "Unknown Generator Platform ${SYSTEM_PROCESSOR}")
        endif()
    else()
        # Translate target architecture into corresponding OpenSSL build flag
        if (${SYSTEM_PROCESSOR} STREQUAL "arm64")
            set(QUIC_OPENSSL_WIN_ARCH "VC-WIN64-ARM")
        elseif (${SYSTEM_PROCESSOR} STREQUAL "arm")
            set(QUIC_OPENSSL_WIN_ARCH "VC-WIN32-ARM")
        elseif (${SYSTEM_PROCESSOR} STREQUAL "win32" OR ${SYSTEM_PROCESSOR} STREQUAL "x86")
            set(QUIC_OPENSSL_WIN_ARCH "VC-WIN32")
        elseif (${SYSTEM_PROCESSOR} STREQUAL "x64" OR ${SYSTEM_PROCESSOR} STREQUAL "amd64")
            set(QUIC_OPENSSL_WIN_ARCH "VC-WIN64A")
        else()
            message(FATAL_ERROR "Unknown Generator Platform ${SYSTEM_PROCESSOR}")
        endif()
    endif()

    set(OPENSSL_EXTRA_CONFIGURE_ARGS "")

    if(HAS_SPECTRE)
        list(APPEND OPENSSL_EXTRA_CONFIGURE_ARGS /Qspectre)
    endif()

    # guard:cf does not work on OpenSSL
    # https://github.com/openssl/openssl/issues/16147
    # if(HAS_GUARDCF)
    #     list(APPEND OPENSSL_EXTRA_CONFIGURE_ARGS /guard:cf)
    # endif()

    find_program(JOM_EXE jom)
    if (JOM_EXE)
        list(APPEND OPENSSL_EXTRA_CONFIGURE_ARGS /FS)
        include(ProcessorCount)
        ProcessorCount(NPROCS)
        set(OPENSSL_RUN_COMMAND "${JOM_EXE}" -j${NPROCS})
    else()

        set(OPENSSL_RUN_COMMAND nmake)
    endif()

    list(APPEND OPENSSL_CONFIG_FLAGS
        ${QUIC_OPENSSL_WIN_ARCH} ${OPENSSL_EXTRA_CONFIGURE_ARGS})

    if (QUIC_UWP_BUILD)
        list(APPEND OPENSSL_CONFIG_FLAGS no-async)
    endif()

    # Create working and output directories as needed
    file(MAKE_DIRECTORY ${OPENSSL_DIR}/debug/include)
    file(MAKE_DIRECTORY ${OPENSSL_DIR}/release/include)
    file(MAKE_DIRECTORY ${QUIC_BUILD_DIR}/${QUIC_OPENSSL}/quictls/debug)
    file(MAKE_DIRECTORY ${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/release)

    # Configure steps for debug and release variants
    add_custom_command(
        WORKING_DIRECTORY $<IF:$<CONFIG:Debug>,${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/debug,${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/release>
        OUTPUT $<IF:$<CONFIG:Debug>,${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/debug/makefile,${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/release/makefile>
        COMMAND perl ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/Configure ${OPENSSL_CONFIG_FLAGS} $<$<CONFIG:Debug>:--debug> $<$<CONFIG:Debug>:--prefix=${OPENSSL_DIR}/debug> $<$<NOT:$<CONFIG:Debug>>:--prefix=${OPENSSL_DIR}/release>

        COMMENT "OpenSSL configure"
    )

    # Compile/install commands for debug and release variants
    add_custom_command(
        OUTPUT $<IF:$<CONFIG:Debug>,${LIBSSL_DEBUG_PATH},${LIBSSL_PATH}>
        OUTPUT $<IF:$<CONFIG:Debug>,${LIBCRYPTO_DEBUG_PATH},${LIBCRYPTO_PATH}>
        DEPENDS $<IF:$<CONFIG:Debug>,${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/debug/makefile,${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/release/makefile>
        WORKING_DIRECTORY $<IF:$<CONFIG:Debug>,${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/debug,${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/release>
        COMMAND ${OPENSSL_RUN_COMMAND} install_dev
        COMMENT "OpenSSL build"
    )

    # Named target depending on the final lib artifacts produced by custom commands
    add_custom_target(
        OpenSSL_Target
        DEPENDS
        $<$<CONFIG:Debug>:${LIBSSL_DEBUG_PATH}>
        $<$<NOT:$<CONFIG:Debug>>:${LIBSSL_PATH}>
        $<$<CONFIG:Debug>:${LIBCRYPTO_DEBUG_PATH}>
        $<$<NOT:$<CONFIG:Debug>>:${LIBCRYPTO_PATH}>
    )
    set_property(TARGET OpenSSL_Target PROPERTY FOLDER "${QUIC_FOLDER_PREFIX}helpers")

    # Target to export to parent project
    add_library(OpenSSLQuic INTERFACE)
    add_dependencies(OpenSSLQuic
        OpenSSL_Target)
    target_include_directories(
        OpenSSLQuic
        INTERFACE
        $<BUILD_INTERFACE:$<$<CONFIG:Debug>:${OPENSSL_DIR}/debug/include>
        $<$<NOT:$<CONFIG:Debug>>:${OPENSSL_DIR}/release/include>>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
    )
    target_link_libraries(
        OpenSSLQuic
        INTERFACE
        $<$<CONFIG:Debug>:${LIBSSL_DEBUG_PATH}>
        $<$<CONFIG:Debug>:${LIBCRYPTO_DEBUG_PATH}>
        $<$<NOT:$<CONFIG:Debug>>:${LIBSSL_PATH}>
        $<$<NOT:$<CONFIG:Debug>>:${LIBCRYPTO_PATH}>
    )

    add_library(MsQuic::OpenSSL ALIAS OpenSSLQuic)

else()

    set(LIBSSL_PATH ${OPENSSL_DIR}/lib/libssl${CMAKE_STATIC_LIBRARY_SUFFIX})
    set(LIBCRYPTO_PATH ${OPENSSL_DIR}/lib/libcrypto${CMAKE_STATIC_LIBRARY_SUFFIX})

    # Figure out the default cert directory
    execute_process(
        COMMAND openssl version -d
        RESULT_VARIABLE OPENSSL_VERSION_RESULT
        OUTPUT_VARIABLE FULL_OPENSSL_CERT_DIR)

    if (OPENSSL_VERSION_RESULT STREQUAL 0)
        # PARSE OPENSSLDIR
        string(REGEX MATCH "OPENSSLDIR:.*\"(.+)\"" OPENSSL_CERT_MATCH_VAR ${FULL_OPENSSL_CERT_DIR})
        if (CMAKE_MATCH_COUNT EQUAL 1)
            message(STATUS "Setting openssldir to ${CMAKE_MATCH_1}")
            list(APPEND OPENSSL_CONFIG_FLAGS --openssldir=\"${CMAKE_MATCH_1}\")
            set(CONFIGURED_OPENSSL_CERT_DIR TRUE)
        endif()
    endif()

    if (NOT CONFIGURED_OPENSSL_CERT_DIR)
        message(STATUS "Setting openssldir to default /usr/local/ssl")
        list(APPEND OPENSSL_CONFIG_FLAGS --openssldir=/usr/local/ssl)
    endif()

    list(APPEND OPENSSL_CONFIG_FLAGS --prefix=${OPENSSL_DIR})

    if (NOT QUIC_SKIP_SANITIZE_SUBMODULES)
        if (QUIC_ENABLE_ASAN)
            message(STATUS "Configuring ASAN for ${QUIC_OPENSSL}")
            list(APPEND OPENSSL_CONFIG_FLAGS enable-asan)
        endif()

        if (QUIC_ENABLE_UBSAN)
            message(STATUS "Configuring UBSAN for ${QUIC_OPENSSL}")
            list(APPEND OPENSSL_CONFIG_FLAGS enable-ubsan)
        endif()
    endif()
    if(ANDROID)
        message(STATUS "${ANDROID_ABI}")
        if(ANDROID_ABI STREQUAL "arm64-v8a")
            set(OPENSSL_BUILD_TYPE android-arm64)
        elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
            set(OPENSSL_BUILD_TYPE android-arm)
        elseif(ANDROID_ABI STREQUAL "x86")
            set(OPENSSL_BUILD_TYPE android-x86)
        elseif(ANDROID_ABI STREQUAL "x86_64")
            set(OPENSSL_BUILD_TYPE android-x86_64)
        else()
            message(FATAL_ERROR "Unknown android abi type")
        endif()
        # On a Windows host, Configure is a Perl script and cannot be executed
        # directly (no shebang support); invoke perl explicitly.
        if(CMAKE_HOST_WIN32)
            # Prefer Strawberry Perl (full CPAN modules needed by OpenSSL)
            find_program(PERL_EXECUTABLE perl
                HINTS "C:/Strawberry/perl/bin"
                REQUIRED)
            set(OPENSSL_CONFIG_CMD ${PERL_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/Configure
                ${OPENSSL_BUILD_TYPE}
                -D__ANDROID_API__=29)
            # Convert the Windows perl path (C:/...) to MSYS-style (/c/...)
            # so sh.exe (used by GNU make) can execute Perl without misinterpreting
            # backslashes as escape sequences.
            string(REGEX REPLACE "^([A-Za-z]):" "/\\1" PERL_MSYS "${PERL_EXECUTABLE}")
            string(TOLOWER "${PERL_MSYS}" PERL_MSYS)
        else()
            set(OPENSSL_CONFIG_CMD ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/Configure
                ${OPENSSL_BUILD_TYPE}
                -D__ANDROID_API__=29)
        endif()
        # no-asm: skip assembly generators (which use Unix-only CC=value cmd syntax)
        # so the OpenSSL Makefile is compatible with cmd.exe on a Windows host.
        list(APPEND OPENSSL_CONFIG_FLAGS no-asm)
    elseif (CX_PLATFORM STREQUAL "linux")
        if(CMAKE_SYSTEM_PROCESSOR STREQUAL arm)
            set(OPENSSL_CONFIG_CMD ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/Configure
                linux-armv4 -DL_ENDIAN
                --cross-compile-prefix=${GNU_MACHINE}${FLOAT_ABI_SUFFIX}-)
            list(APPEND OPENSSL_CONFIG_FLAGS -latomic)
        else()
            if (CMAKE_TARGET_ARCHITECTURE STREQUAL arm64)
                if (ONEBRANCH)
                    set(OPENSSL_CONFIG_CMD ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/Configure linux-aarch64
                    --cross-compile-prefix=${GNU_MACHINE}${FLOAT_ABI_SUFFIX}-)
                else()
                    set(OPENSSL_CONFIG_CMD ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/Configure linux-aarch64)
                    check_c_compiler_flag(--target=aarch64-linux-gnu HAVE_AARCH64_TARGET)
                    if (HAVE_AARCH64_TARGET)
                        list(APPEND OPENSSL_CONFIG_FLAGS --target=aarch64-linux-gnu)
                    endif()
                endif()
                list(APPEND OPENSSL_CONFIG_FLAGS -latomic)
            elseif (CMAKE_TARGET_ARCHITECTURE STREQUAL arm)
                if (ONEBRANCH)
                    set(OPENSSL_CONFIG_CMD ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/Configure linux-armv4
                    --cross-compile-prefix=${GNU_MACHINE}${FLOAT_ABI_SUFFIX}-)
                else()
                    set(OPENSSL_CONFIG_CMD ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/Configure linux-armv4)
                endif()
                list(APPEND OPENSSL_CONFIG_FLAGS -latomic)
            else()
                set(OPENSSL_CONFIG_CMD ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/config
                            CC=${CMAKE_C_COMPILER} CXX=${CMAKE_CXX_COMPILER})
            endif()
        endif()
    elseif(CX_PLATFORM STREQUAL "darwin")
        if (CMAKE_OSX_ARCHITECTURES STREQUAL arm64)
            set(OPENSSL_CONFIG_CMD ARCHFLAGS="-arch arm64" ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/Configure darwin64-arm64-cc)
        elseif(CMAKE_OSX_ARCHITECTURES STREQUAL x86_64)
            set(OPENSSL_CONFIG_CMD ARCHFLAGS="-arch x86_64" ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/Configure darwin64-x86_64-cc)
        else()
            message(ERROR "WTF ${CX_PLATFORM} ${CMAKE_TARGET_ARCHITECTURE}")
            set(OPENSSL_CONFIG_CMD ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/config)
        endif()
        
        if(NOT CMAKE_OSX_SYSROOT)
            execute_process(
                COMMAND xcrun --sdk macosx --show-sdk-path
                OUTPUT_VARIABLE MACOS_SDK_PATH
                OUTPUT_STRIP_TRAILING_WHITESPACE
            )
            if(MACOS_SDK_PATH)
                set(CMAKE_OSX_SYSROOT "${MACOS_SDK_PATH}")
                message(STATUS "Setting macOS SDK path for OpenSSL: ${CMAKE_OSX_SYSROOT}")
            endif()
        endif()
        
        list(APPEND OPENSSL_CONFIG_FLAGS -isysroot ${CMAKE_OSX_SYSROOT})
        
        if(SDK_NAME)
            list(APPEND OPENSSL_CONFIG_FLAGS "-m${SDK_NAME}-version-min=${DEPLOYMENT_TARGET}")
        elseif(CMAKE_OSX_DEPLOYMENT_TARGET)
            string(REPLACE "." "" DEPLOYMENT_TARGET_CLEAN "${CMAKE_OSX_DEPLOYMENT_TARGET}")
            list(APPEND OPENSSL_CONFIG_FLAGS "-mmacosx-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
            message(STATUS "OpenSSL deployment target: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
        endif()
        
        if (ENABLE_BITCODE)
            list(APPEND OPENSSL_CONFIG_FLAGS -fembed-bitcode)
        endif()
    else()
        set(OPENSSL_CONFIG_CMD ${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}/config
            CC=${CMAKE_C_COMPILER} CXX=${CMAKE_CXX_COMPILER})
    endif()

    # Create working and output directories as needed
    file(MAKE_DIRECTORY ${OPENSSL_DIR}/include)
    file(MAKE_DIRECTORY ${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL})

    # Configure steps for debug and release variants
    # Use cmake -E env to set SYSTEM portably (avoids Unix-only VAR=value cmd syntax
    # which fails when the host shell is cmd.exe on Windows).
    # Also pass ANDROID_NDK_ROOT which OpenSSL's Configure requires for android targets.
    if(ANDROID)
        # Convert backslashes to forward slashes — OpenSSL's Perl Configure uses
        # ANDROID_NDK_ROOT in regex patterns, so Windows backslashes break parsing.
        string(REPLACE "\\" "/" ANDROID_NDK_FWDSLASH "${ANDROID_NDK}")
        # CONFIGURE_CHECKER_WARN=1 demotes the unix-checker.pm fatal error (which
        # rejects MSWin32 Perl) to a warning so cross-compilation can proceed.
        set(OPENSSL_ENV_ARGS "SYSTEM=${CMAKE_HOST_SYSTEM_NAME}" "ANDROID_NDK_ROOT=${ANDROID_NDK_FWDSLASH}" "CONFIGURE_CHECKER_WARN=1")
    else()
        set(OPENSSL_ENV_ARGS "SYSTEM=${CMAKE_HOST_SYSTEM_NAME}")
    endif()
    # On Windows with Android target: after Configure, patch the generated Makefile
    # to replace backslash path separators with forward slashes so that sh.exe
    # (GNU make's POSIX shell, required for the for/do loop recipes) does not
    # mangle unquoted Windows paths.  Also set SHELL=sh.exe so make uses sh.exe.
    if(ANDROID AND CMAKE_HOST_WIN32)
        set(MAKE_EXTRA_ARGS "SHELL=C:/GitSh/sh.exe")
        set(OPENSSL_MAKEFILE_PATCHED ${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/Makefile.win_patched)
    else()
        set(MAKE_EXTRA_ARGS)
    endif()
    # The upstream OpenSSL submodule cannot carry our Windows-host build fixes (a
    # submodule records only a commit pointer, not file edits, and we don't own the
    # repo). Those fixes live as patches under submodules/patches/ and are applied to
    # the submodule source *before* Configure runs, since Configure reads the patched
    # Configurations/15-android.conf. The apply step is idempotent (see
    # apply_openssl_patches.cmake).
    if(ANDROID AND CMAKE_HOST_WIN32)
        set(OPENSSL_PATCH_STAMP ${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/openssl_patches.applied)
        add_custom_command(
            OUTPUT ${OPENSSL_PATCH_STAMP}
            COMMAND ${CMAKE_COMMAND}
                -DOPENSSL_SRC=${CMAKE_CURRENT_SOURCE_DIR}/${QUIC_OPENSSL}
                -DPATCH_FILE=${CMAKE_CURRENT_SOURCE_DIR}/patches/openssl-15-android-windows.patch
                -P ${CMAKE_CURRENT_SOURCE_DIR}/apply_openssl_patches.cmake
            COMMAND ${CMAKE_COMMAND} -E touch ${OPENSSL_PATCH_STAMP}
            COMMENT "Apply OpenSSL Windows-host patches"
        )
        set(OPENSSL_CONFIGURE_DEPENDS ${OPENSSL_PATCH_STAMP})
    else()
        set(OPENSSL_CONFIGURE_DEPENDS)
    endif()
    add_custom_command(
        WORKING_DIRECTORY ${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}
        OUTPUT ${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/Makefile
        DEPENDS ${OPENSSL_CONFIGURE_DEPENDS}
        COMMAND ${CMAKE_COMMAND} -E env ${OPENSSL_ENV_ARGS}
            ${OPENSSL_CONFIG_CMD} ${OPENSSL_CONFIG_FLAGS}
        COMMENT "OpenSSL configure"
    )

    if(ANDROID AND CMAKE_HOST_WIN32)
        # Patch the generated Makefile: replace every backslash path separator
        # with a forward slash using a cmake -P script (avoids shell quoting issues).
        add_custom_command(
            WORKING_DIRECTORY ${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}
            OUTPUT ${OPENSSL_MAKEFILE_PATCHED}
            DEPENDS ${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/Makefile
            COMMAND ${CMAKE_COMMAND}
                -DMAKEFILE_PATH=${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/Makefile
                -P ${CMAKE_CURRENT_SOURCE_DIR}/fix_openssl_makefile.cmake
            COMMAND ${CMAKE_COMMAND} -E touch ${OPENSSL_MAKEFILE_PATCHED}
            COMMENT "Patch OpenSSL Makefile backslash paths for sh.exe compatibility"
        )
    endif()

    include(ProcessorCount)
    ProcessorCount(NPROCS)

    message(STATUS "Configuring OpenSSL: ${OPENSSL_CONFIG_CMD} ${OPENSSL_CONFIG_FLAGS}")
    # Compile/install commands for debug and release variants
    if(ANDROID AND CMAKE_HOST_WIN32)
        set(OPENSSL_MAKE_DEPENDS ${OPENSSL_MAKEFILE_PATCHED})
    else()
        set(OPENSSL_MAKE_DEPENDS ${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}/Makefile)
    endif()
    add_custom_command(
        OUTPUT ${LIBSSL_PATH}
        OUTPUT ${LIBCRYPTO_PATH}
        DEPENDS ${OPENSSL_MAKE_DEPENDS}
        WORKING_DIRECTORY ${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}
        COMMAND ${CMAKE_COMMAND} -E env "SYSTEM=${CMAKE_HOST_SYSTEM_NAME}" make ${MAKE_EXTRA_ARGS} install_dev -j${NPROCS}
        COMMENT "OpenSSL build"
    )

    if (QUIC_USE_SYSTEM_LIBCRYPTO)
        # OpenSSL 3 uses different sources for static and dynamic libraries.
        # That is ok if you use either one consistently but it fails to link when we use dynamic crypto with static ssl.
        # To fix that we need little hackery - see quictls/ssl/build.info
        add_custom_command(
            OUTPUT ${LIBSSL_PATH}
            OUTPUT ${LIBCRYPTO_PATH}
            APPEND
            WORKING_DIRECTORY ${QUIC_BUILD_DIR}/submodules/${QUIC_OPENSSL}
            COMMAND ar x ${LIBCRYPTO_PATH} libcrypto-lib-packet.o libcommon-lib-tls_pad.o
            COMMAND ar r ${LIBSSL_PATH} libcrypto-lib-packet.o libcommon-lib-tls_pad.o
        )
    endif()

    # Named target depending on the final lib artifacts produced by custom commands
    add_custom_target(
        OpenSSL_Target
        DEPENDS
        ${LIBSSL_PATH}
        ${LIBCRYPTO_PATH}
    )
    set_property(TARGET OpenSSL_Target PROPERTY FOLDER "${QUIC_FOLDER_PREFIX}helpers")

    # Target to export to parent project
    add_library(OpenSSLQuic INTERFACE)
    add_dependencies(OpenSSLQuic
        OpenSSL_Target)
    target_include_directories(
        OpenSSLQuic
        INTERFACE
        $<BUILD_INTERFACE:${OPENSSL_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
    )

    target_link_libraries(
        OpenSSLQuic
        INTERFACE
        ${LIBSSL_PATH}
    )

    if (QUIC_USE_SYSTEM_LIBCRYPTO)
        include(FindOpenSSL)
        if (OPENSSL_FOUND)
            # Get Major.Minor so 3.0 can match 3.0.2.
            # We cannot use VERSION_GREATER as 3.0 would work for 1.1.1 but they are not compatible.
            string(FIND ${OPENSSL_VERSION} "." VERSIONLEN REVERSE)
            string(SUBSTRING ${OPENSSL_VERSION} 0 ${VERSIONLEN}  OPENSSL_MAJORMINOR)
            string(FIND ${OPENSSL_VERSION} "." VERSIONLEN)
            string(SUBSTRING ${OPENSSL_VERSION} 0 ${VERSIONLEN}  OPENSSL_MAJOR)
            if (OPENSSL_VERSION VERSION_EQUAL EXPECTED_OPENSSL_VERSION OR OPENSSL_MAJORMINOR VERSION_EQUAL EXPECTED_OPENSSL_VERSION OR
                # 3.1 is compatible with 3.0, 3.2 and beyond maybe as well.
                (EXPECTED_OPENSSL_VERSION VERSION_EQUAL "3.0" AND OPENSSL_MAJOR EQUAL "3"))
                target_link_libraries(OpenSSLQuic INTERFACE OpenSSL::Crypto)
            else()
                message(FATAL_ERROR "OpenSSL ${EXPECTED_OPENSSL_VERSION} not found, found ${OPENSSL_VERSION}")
            endif()
        else()
            message(FATAL_ERROR "System OpenSSL not found when requested")
        endif()
    else()
        target_link_libraries(
            OpenSSLQuic
            INTERFACE
            ${LIBCRYPTO_PATH}
        )
    endif()

    add_library(MsQuic::OpenSSL ALIAS OpenSSLQuic)

endif()
