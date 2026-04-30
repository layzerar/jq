# CMake build for jq
#
# This is an alternative to the autoconf + automake build defined by
# `configure.ac` and `Makefile.am`. It mirrors their behavior closely:
# the same set of HAVE_* / USE_DECNUM / IEEE_* preprocessor symbols is
# probed and exposed to the source tree, the same libjq + jq targets are
# produced, and the same shell-based test drivers under `tests/` are
# wired up via `enable_testing()`.
#
# Quick start:
#
#   cmake -S . -B build -DJQ_BUILD_ONIGURUMA=builtin
#   cmake --build build -j
#   ctest --test-dir build --output-on-failure

cmake_minimum_required(VERSION 3.16)

# Fallback version string used when scripts/version (git describe) is
# unavailable. Kept in sync with the project version below.
set(_jq_fallback_version "1.8.0")

project(jq
  VERSION 1.8.0
  DESCRIPTION "Command-line JSON processor"
  HOMEPAGE_URL "https://jqlang.org"
  LANGUAGES C)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

include(GNUInstallDirs)
include(CheckCSourceCompiles)
include(CheckIncludeFile)
include(CheckFunctionExists)
include(CheckLibraryExists)
include(CheckSymbolExists)
include(CheckTypeSize)
include(CheckStructHasMember)
include(TestBigEndian)

# --------------------------------------------------------------------------
# User-facing options (mirroring configure.ac AC_ARG_ENABLE / AC_ARG_WITH)
# --------------------------------------------------------------------------

set(JQ_BUILD_ONIGURUMA "auto" CACHE STRING
  "Oniguruma support: auto (system if found, else off), system, builtin, or off")
set_property(CACHE JQ_BUILD_ONIGURUMA PROPERTY STRINGS auto system builtin off)

option(JQ_ENABLE_DECNUM    "Enable decNumber support"               ON)
option(JQ_ENABLE_ASAN      "Enable AddressSanitizer"                OFF)
option(JQ_ENABLE_UBSAN     "Enable UndefinedBehaviorSanitizer"      OFF)
option(JQ_ENABLE_GCOV      "Enable gcov code coverage"              OFF)
option(JQ_ENABLE_ALL_STATIC "Link the jq executable fully statically" OFF)
option(JQ_ENABLE_ERROR_INJECTION "Build the libinject_errors helper" OFF)
option(JQ_BUILD_TESTS      "Build/register the jq test suite"       ON)
option(JQ_BUILD_SHARED_LIB "Build libjq as a shared library"        ON)
option(JQ_BUILD_STATIC_LIB "Build libjq as a static library"        ON)
option(JQ_INSTALL          "Generate install rules"                 ON)

if(NOT JQ_BUILD_SHARED_LIB AND NOT JQ_BUILD_STATIC_LIB)
  message(FATAL_ERROR
    "At least one of JQ_BUILD_SHARED_LIB / JQ_BUILD_STATIC_LIB must be ON")
endif()

# --------------------------------------------------------------------------
# Compiler flags (mirroring AM_CFLAGS in Makefile.am)
# --------------------------------------------------------------------------

set(JQ_C_WARNINGS
  -Wextra -Wall
  -Wno-unused-parameter -Wno-unused-function
  -Woverlength-strings -Wstrict-prototypes)

# Filter to flags actually accepted by the compiler.
include(CheckCCompilerFlag)
set(_jq_supported_warnings)
foreach(_flag IN LISTS JQ_C_WARNINGS)
  string(MAKE_C_IDENTIFIER "HAS_FLAG_${_flag}" _var)
  check_c_compiler_flag("${_flag}" ${_var})
  if(${_var})
    list(APPEND _jq_supported_warnings "${_flag}")
  endif()
endforeach()

# Sanitizers / coverage flags propagate everywhere (they need to be on both
# compile and link lines).
set(_jq_extra_compile_flags "")
set(_jq_extra_link_flags "")
if(JQ_ENABLE_ASAN)
  list(APPEND _jq_extra_compile_flags -fsanitize=address)
  list(APPEND _jq_extra_link_flags    -fsanitize=address)
endif()
if(JQ_ENABLE_UBSAN)
  list(APPEND _jq_extra_compile_flags -fsanitize=undefined)
  list(APPEND _jq_extra_link_flags    -fsanitize=undefined)
endif()
if(JQ_ENABLE_GCOV)
  list(APPEND _jq_extra_compile_flags --coverage)
  list(APPEND _jq_extra_link_flags    --coverage)
endif()

# Detect Windows (matches WIN32 conditional in Makefile.am: shlwapi without
# cygwin). CMake's WIN32 already handles MinGW/MSVC; we still also probe
# shlwapi.h to define the same symbol the autoconf path uses.
check_include_file("shlwapi.h" HAVE_SHLWAPI_H)
check_include_file("sys/cygwin.h" HAVE_CYGWIN_H)
if(HAVE_SHLWAPI_H AND NOT HAVE_CYGWIN_H)
  set(JQ_WIN32 TRUE)
else()
  set(JQ_WIN32 FALSE)
endif()

# --------------------------------------------------------------------------
# Feature checks (mirroring configure.ac)
# --------------------------------------------------------------------------

set(_jq_required_libs "")
set(_jq_compile_defs "_GNU_SOURCE;_DARWIN_C_SOURCE")  # AC_USE_SYSTEM_EXTENSIONS

# Threads (AX_PTHREAD): enables HAVE_PTHREAD when available.
set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads)
set(HAVE_PTHREAD FALSE)
if(Threads_FOUND AND CMAKE_USE_PTHREADS_INIT)
  set(HAVE_PTHREAD TRUE)
endif()

# Largefile support (AC_SYS_LARGEFILE).
list(APPEND _jq_compile_defs _FILE_OFFSET_BITS=64)

# Helper that probes a function (like AC_FIND_FUNC) and defines HAVE_<FUNC>.
function(_jq_check_func sym header outvar)
  set(CMAKE_REQUIRED_DEFINITIONS "-D_GNU_SOURCE")
  check_symbol_exists("${sym}" "${header}" ${outvar})
  set(${outvar} ${${outvar}} PARENT_SCOPE)
endfunction()

_jq_check_func(memmem      "string.h"   HAVE_MEMMEM)
_jq_check_func(isatty      "unistd.h"   HAVE_ISATTY)
_jq_check_func(_isatty     "io.h"       HAVE__ISATTY)
_jq_check_func(strptime    "time.h"     HAVE_STRPTIME)
_jq_check_func(strftime    "time.h"     HAVE_STRFTIME)
_jq_check_func(setenv      "stdlib.h"   HAVE_SETENV)
_jq_check_func(timegm      "time.h"     HAVE_TIMEGM)
_jq_check_func(gmtime_r    "time.h"     HAVE_GMTIME_R)
_jq_check_func(gmtime      "time.h"     HAVE_GMTIME)
_jq_check_func(localtime_r "time.h"     HAVE_LOCALTIME_R)
_jq_check_func(localtime   "time.h"     HAVE_LOCALTIME)
_jq_check_func(gettimeofday "sys/time.h" HAVE_GETTIMEOFDAY)
_jq_check_func(setlocale   "locale.h"   HAVE_SETLOCALE)
_jq_check_func(arc4random  "stdlib.h"   HAVE_ARC4RANDOM)
_jq_check_func(getentropy  "unistd.h"   HAVE_GETENTROPY)

# struct tm members
check_struct_has_member("struct tm" tm_gmtoff   "time.h" HAVE_TM_TM_GMT_OFF)
check_struct_has_member("struct tm" __tm_gmtoff "time.h" HAVE_TM___TM_GMT_OFF)

# alloca: AC_FUNC_ALLOCA defines HAVE_ALLOCA / HAVE_ALLOCA_H.
check_include_file("alloca.h" HAVE_ALLOCA_H)
check_symbol_exists(alloca "alloca.h;stdlib.h;malloc.h" HAVE_ALLOCA)

# pthread-specific functions used by jv_alloc.c.
if(HAVE_PTHREAD)
  set(CMAKE_REQUIRED_LIBRARIES "Threads::Threads")
  check_symbol_exists(pthread_key_create "pthread.h" HAVE_PTHREAD_KEY_CREATE)
  check_symbol_exists(pthread_once       "pthread.h" HAVE_PTHREAD_ONCE)
  unset(CMAKE_REQUIRED_LIBRARIES)
endif()
check_symbol_exists(atexit "stdlib.h" HAVE_ATEXIT)

# Math functions (mirroring AC_CHECK_MATH_FUNC from config/m4/jq.m4).
set(_jq_math_funcs
  acos acosh asin asinh atan2 atan atanh cbrt ceil copysign cos cosh
  drem erf erfc exp10 __exp10 exp2 exp expm1 fabs fdim floor fma fmax
  fmin fmod frexp gamma hypot j0 j1 jn ldexp lgamma log10 log1p log2
  log logb modf lgamma_r nearbyint nextafter nexttoward pow remainder
  rint round scalb scalbln significand scalbn ilogb sin sinh sqrt tan
  tanh tgamma trunc y0 y1 yn)

set(CMAKE_REQUIRED_LIBRARIES "m")
foreach(_fn IN LISTS _jq_math_funcs)
  string(TOUPPER "${_fn}" _upper)
  string(REGEX REPLACE "[^A-Z0-9_]" "_" _upper "${_upper}")
  set(_var "HAVE_${_upper}")
  check_symbol_exists("${_fn}" "math.h" ${_var})
endforeach()
unset(CMAKE_REQUIRED_LIBRARIES)

# libm itself
check_library_exists(m sin "" _jq_have_libm)
if(_jq_have_libm)
  list(APPEND _jq_required_libs m)
endif()

# Thread-local storage (AC_LINK_IFELSE for __thread)
check_c_source_compiles([[
static __thread int x;
int main(void) { x = 123; return x; }
]] HAVE___THREAD)

# Endianness
test_big_endian(_jq_big_endian)
if(_jq_big_endian)
  set(IEEE_MC68k 1)
else()
  set(IEEE_8087 1)
endif()

# decnum support
if(JQ_ENABLE_DECNUM)
  set(USE_DECNUM 1)
endif()

# --------------------------------------------------------------------------
# Translate the probed values into compile definitions
# --------------------------------------------------------------------------

set(_jq_have_vars
  HAVE_PTHREAD HAVE_MEMMEM HAVE_ISATTY HAVE__ISATTY HAVE_STRPTIME
  HAVE_STRFTIME HAVE_SETENV HAVE_TIMEGM HAVE_GMTIME_R HAVE_GMTIME
  HAVE_LOCALTIME_R HAVE_LOCALTIME HAVE_GETTIMEOFDAY HAVE_SETLOCALE
  HAVE_ARC4RANDOM HAVE_GETENTROPY HAVE_TM_TM_GMT_OFF HAVE_TM___TM_GMT_OFF
  HAVE_ALLOCA HAVE_ALLOCA_H HAVE_PTHREAD_KEY_CREATE HAVE_PTHREAD_ONCE
  HAVE_ATEXIT HAVE___THREAD)
foreach(_fn IN LISTS _jq_math_funcs)
  string(TOUPPER "${_fn}" _upper)
  string(REGEX REPLACE "[^A-Z0-9_]" "_" _upper "${_upper}")
  list(APPEND _jq_have_vars "HAVE_${_upper}")
endforeach()

foreach(_v IN LISTS _jq_have_vars)
  if(${_v})
    list(APPEND _jq_compile_defs "${_v}=1")
  endif()
endforeach()

if(USE_DECNUM)
  list(APPEND _jq_compile_defs USE_DECNUM=1)
endif()
if(IEEE_MC68k)
  list(APPEND _jq_compile_defs IEEE_MC68k=1)
endif()
if(IEEE_8087)
  list(APPEND _jq_compile_defs IEEE_8087=1)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "SunOS")
  list(APPEND _jq_compile_defs _STRPTIME_DONTZERO)
endif()

# --------------------------------------------------------------------------
# Oniguruma
# --------------------------------------------------------------------------

set(_jq_onig_target "")
set(_jq_use_oniguruma FALSE)

if(NOT JQ_BUILD_ONIGURUMA STREQUAL "off")
  if(JQ_BUILD_ONIGURUMA STREQUAL "builtin")
    set(_try_builtin TRUE)
    set(_try_system  FALSE)
  elseif(JQ_BUILD_ONIGURUMA STREQUAL "system")
    set(_try_builtin FALSE)
    set(_try_system  TRUE)
  else() # auto
    set(_try_builtin TRUE)
    set(_try_system  TRUE)
  endif()

  if(_try_system)
    find_path(ONIG_INCLUDE_DIR NAMES oniguruma.h)
    find_library(ONIG_LIBRARY NAMES onig)
    if(ONIG_INCLUDE_DIR AND ONIG_LIBRARY)
      add_library(jq_onig INTERFACE)
      target_include_directories(jq_onig INTERFACE "${ONIG_INCLUDE_DIR}")
      target_link_libraries(jq_onig INTERFACE "${ONIG_LIBRARY}")
      set(_jq_onig_target jq_onig)
      set(_jq_use_oniguruma TRUE)
      message(STATUS "Using system oniguruma: ${ONIG_LIBRARY}")
    elseif(JQ_BUILD_ONIGURUMA STREQUAL "system")
      message(FATAL_ERROR
        "JQ_BUILD_ONIGURUMA=system requested but oniguruma was not found")
    endif()
  endif()

  if(NOT _jq_use_oniguruma AND _try_builtin)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/vendor/oniguruma/CMakeLists.txt")
      # The vendored oniguruma honors BUILD_SHARED_LIBS; build it as a static
      # library so the jq executable doesn't depend on a separate .so.
      set(_saved_BUILD_SHARED_LIBS ${BUILD_SHARED_LIBS})
      set(BUILD_SHARED_LIBS OFF)
      add_subdirectory(vendor/oniguruma EXCLUDE_FROM_ALL)
      set(BUILD_SHARED_LIBS ${_saved_BUILD_SHARED_LIBS})
      # We may link the static onig into our shared libjq, so it needs PIC.
      if(TARGET onig)
        set_target_properties(onig PROPERTIES POSITION_INDEPENDENT_CODE ON)
      endif()
      set(_jq_onig_target onig)
      set(_jq_use_oniguruma TRUE)
      message(STATUS "Using bundled oniguruma (vendor/oniguruma)")
    elseif(JQ_BUILD_ONIGURUMA STREQUAL "builtin")
      message(FATAL_ERROR
        "JQ_BUILD_ONIGURUMA=builtin requested but vendor/oniguruma is empty.\n"
        "Run: git submodule update --init")
    else()
      message(STATUS "Oniguruma not available; building without regex support")
    endif()
  endif()
endif()

if(_jq_use_oniguruma)
  list(APPEND _jq_compile_defs HAVE_LIBONIG=1)
endif()

# --------------------------------------------------------------------------
# Generated sources: src/version.h, src/config_opts.inc, src/builtin.inc
# --------------------------------------------------------------------------

set(_jq_gen_dir "${CMAKE_CURRENT_BINARY_DIR}/src")
file(MAKE_DIRECTORY "${_jq_gen_dir}")

# version.h: regenerated at every build because it depends on git state.
add_custom_target(jq_version_h ALL
  BYPRODUCTS "${_jq_gen_dir}/version.h"
  COMMAND "${CMAKE_COMMAND}"
          "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}"
          "-DOUTPUT=${_jq_gen_dir}/version.h"
          "-DFALLBACK=${PROJECT_VERSION}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/GenerateVersionH.cmake"
  COMMENT "Generating src/version.h"
  VERBATIM)

# config_opts.inc: a fixed string describing the CMake configuration.
set(_jq_config_opts "cmake")
if(JQ_ENABLE_DECNUM)
  string(APPEND _jq_config_opts " --enable-decnum")
else()
  string(APPEND _jq_config_opts " --disable-decnum")
endif()
if(_jq_use_oniguruma)
  string(APPEND _jq_config_opts " --with-oniguruma=${JQ_BUILD_ONIGURUMA}")
else()
  string(APPEND _jq_config_opts " --without-oniguruma")
endif()
add_custom_command(
  OUTPUT "${_jq_gen_dir}/config_opts.inc"
  COMMAND "${CMAKE_COMMAND}"
          "-DOUTPUT=${_jq_gen_dir}/config_opts.inc"
          "-DOPTS=${_jq_config_opts}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/GenerateConfigOptsInc.cmake"
  COMMENT "Generating src/config_opts.inc"
  VERBATIM)

# builtin.inc: encoded copy of src/builtin.jq.
add_custom_command(
  OUTPUT "${_jq_gen_dir}/builtin.inc"
  COMMAND "${CMAKE_COMMAND}"
          "-DINPUT=${CMAKE_CURRENT_SOURCE_DIR}/src/builtin.jq"
          "-DOUTPUT=${_jq_gen_dir}/builtin.inc"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/GenerateBuiltinInc.cmake"
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/builtin.jq"
          "${CMAKE_CURRENT_SOURCE_DIR}/cmake/GenerateBuiltinInc.cmake"
  COMMENT "Generating src/builtin.inc"
  VERBATIM)

add_custom_target(jq_generated_sources
  DEPENDS "${_jq_gen_dir}/builtin.inc" "${_jq_gen_dir}/config_opts.inc")
add_dependencies(jq_generated_sources jq_version_h)

# Source code includes generated files using paths like "src/builtin.inc",
# so the *parent* of _jq_gen_dir (i.e. the build dir) must be on the include
# path along with the source dir.
set(_jq_include_dirs
  "${CMAKE_CURRENT_BINARY_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${CMAKE_CURRENT_SOURCE_DIR}/vendor")

# --------------------------------------------------------------------------
# libjq sources (mirroring LIBJQ_SRC / LIBJQ_INCS in Makefile.am)
# --------------------------------------------------------------------------

set(LIBJQ_HEADERS
  src/builtin.h src/bytecode.h src/compile.h src/exec_stack.h
  src/jq_parser.h src/jv_alloc.h src/jv_dtoa.h src/jv_unicode.h
  src/jv_utf8_tables.h src/libm.h src/linker.h src/locfile.h
  src/opcode_list.h src/util.h src/jv_dtoa_tsd.h src/jv_thread.h
  src/jv_private.h
  vendor/decNumber/decContext.h vendor/decNumber/decNumber.h
  vendor/decNumber/decNumberLocal.h)

set(LIBJQ_SOURCES
  src/builtin.c src/bytecode.c src/compile.c src/execute.c
  src/jq_test.c src/jv.c src/jv_alloc.c src/jv_aux.c
  src/jv_dtoa.c src/jv_file.c src/jv_parse.c src/jv_print.c
  src/jv_unicode.c src/linker.c src/locfile.c src/util.c
  src/jv_dtoa_tsd.c
  src/lexer.c src/parser.c
  vendor/decNumber/decContext.c vendor/decNumber/decNumber.c)

# Object library: avoids compiling the same translation units twice when both
# shared and static libjq are produced.
add_library(jq_objects OBJECT ${LIBJQ_SOURCES} ${LIBJQ_HEADERS})
add_dependencies(jq_objects jq_generated_sources)

set_target_properties(jq_objects PROPERTIES
  C_STANDARD 99
  POSITION_INDEPENDENT_CODE ON)
target_include_directories(jq_objects PRIVATE ${_jq_include_dirs})
target_compile_definitions(jq_objects PRIVATE ${_jq_compile_defs})
target_compile_options(jq_objects PRIVATE
  ${_jq_supported_warnings} ${_jq_extra_compile_flags})
if(JQ_WIN32)
  target_compile_options(jq_objects PRIVATE -municode)
endif()
if(_jq_onig_target)
  target_link_libraries(jq_objects PRIVATE ${_jq_onig_target})
endif()
if(HAVE_PTHREAD)
  target_link_libraries(jq_objects PRIVATE Threads::Threads)
endif()

# Helper to apply common settings to libjq variants.
function(_jq_configure_lib tgt)
  set_target_properties(${tgt} PROPERTIES
    OUTPUT_NAME jq
    C_STANDARD 99)
  target_include_directories(${tgt}
    PUBLIC
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
      $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
    PRIVATE
      ${_jq_include_dirs})
  target_compile_definitions(${tgt} PRIVATE ${_jq_compile_defs})
  target_link_options(${tgt} PRIVATE ${_jq_extra_link_flags})
  if(_jq_required_libs)
    target_link_libraries(${tgt} PRIVATE ${_jq_required_libs})
  endif()
  if(HAVE_PTHREAD)
    target_link_libraries(${tgt} PRIVATE Threads::Threads)
  endif()
  if(_jq_onig_target)
    target_link_libraries(${tgt} PRIVATE ${_jq_onig_target})
  endif()
  if(JQ_WIN32)
    target_link_libraries(${tgt} PRIVATE shlwapi)
  endif()
endfunction()

# Shared libjq.
if(JQ_BUILD_SHARED_LIB)
  add_library(libjq_shared SHARED $<TARGET_OBJECTS:jq_objects>)
  add_dependencies(libjq_shared jq_generated_sources)
  _jq_configure_lib(libjq_shared)
  # version-info 1:4:0 -> on most platforms libtool maps to soname libjq.so.1
  set_target_properties(libjq_shared PROPERTIES
    VERSION   1.0.4
    SOVERSION 1)
  add_library(jq::libjq ALIAS libjq_shared)
endif()

# Static libjq.
if(JQ_BUILD_STATIC_LIB)
  add_library(libjq_static STATIC $<TARGET_OBJECTS:jq_objects>)
  add_dependencies(libjq_static jq_generated_sources)
  _jq_configure_lib(libjq_static)
  if(NOT JQ_BUILD_SHARED_LIB)
    add_library(jq::libjq ALIAS libjq_static)
  endif()
  # On Windows the static archive must not collide with the import library
  # for the DLL (both default to jq.lib). Keep the autotools layout where
  # only one of the two is selected at install time anyway.
  if(JQ_BUILD_SHARED_LIB AND WIN32)
    set_target_properties(libjq_static PROPERTIES OUTPUT_NAME jq_static)
  endif()
endif()

# Choose the libjq variant that the jq executable links against. Prefer
# shared (matches the default autotools behavior).
if(JQ_BUILD_SHARED_LIB)
  set(_jq_link_lib libjq_shared)
else()
  set(_jq_link_lib libjq_static)
endif()

# --------------------------------------------------------------------------
# jq executable
# --------------------------------------------------------------------------

add_executable(jq src/main.c)
add_dependencies(jq jq_generated_sources)
set_target_properties(jq PROPERTIES C_STANDARD 99)
target_include_directories(jq PRIVATE ${_jq_include_dirs})
target_compile_definitions(jq PRIVATE ${_jq_compile_defs})
target_compile_options(jq PRIVATE
  ${_jq_supported_warnings} ${_jq_extra_compile_flags})
target_link_options(jq PRIVATE ${_jq_extra_link_flags})
target_link_libraries(jq PRIVATE ${_jq_link_lib})
if(_jq_required_libs)
  target_link_libraries(jq PRIVATE ${_jq_required_libs})
endif()
if(_jq_onig_target)
  # main.c directly includes <oniguruma.h>, so it needs the same include
  # path as libjq.
  target_link_libraries(jq PRIVATE ${_jq_onig_target})
endif()
if(JQ_WIN32)
  target_compile_options(jq PRIVATE -municode)
  target_link_libraries(jq PRIVATE shlwapi)
endif()
if(JQ_ENABLE_ALL_STATIC AND NOT MSVC)
  target_link_options(jq PRIVATE -static)
endif()

# --------------------------------------------------------------------------
# Optional: libinject_errors (LD_PRELOAD test helper)
# --------------------------------------------------------------------------

if(JQ_ENABLE_ERROR_INJECTION)
  add_library(inject_errors MODULE src/inject_errors.c)
  target_link_libraries(inject_errors PRIVATE ${CMAKE_DL_LIBS})
  set_target_properties(inject_errors PROPERTIES
    OUTPUT_NAME inject_errors
    PREFIX "lib")
endif()

# --------------------------------------------------------------------------
# Tests (mirroring the TESTS list in Makefile.am)
# --------------------------------------------------------------------------

if(JQ_BUILD_TESTS)
  enable_testing()
  set(_jq_tests jqtest shtest utf8test base64test uritest)
  if(NOT JQ_WIN32)
    list(APPEND _jq_tests optionaltest)
  endif()
  if(_jq_use_oniguruma)
    list(APPEND _jq_tests onigtest)
  endif()
  # mantest / manonigtest depend on docs being rebuilt from manual.yml,
  # which requires the python toolchain. We skip them in the CMake build.

  find_program(SH_EXECUTABLE NAMES sh REQUIRED)
  foreach(_t IN LISTS _jq_tests)
    set(_drv "${CMAKE_CURRENT_SOURCE_DIR}/tests/${_t}")
    if(EXISTS "${_drv}")
      add_test(NAME ${_t}
        COMMAND "${SH_EXECUTABLE}" "${_drv}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
      set_tests_properties(${_t} PROPERTIES
        ENVIRONMENT "JQ=$<TARGET_FILE:jq>;LC_ALL=C")
    endif()
  endforeach()
endif()

# --------------------------------------------------------------------------
# Installation (mirroring the install rules in Makefile.am)
# --------------------------------------------------------------------------

if(JQ_INSTALL)
  install(TARGETS jq RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

  if(JQ_BUILD_SHARED_LIB)
    install(TARGETS libjq_shared
      EXPORT jqTargets
      LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
      ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
      RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
  endif()
  if(JQ_BUILD_STATIC_LIB)
    install(TARGETS libjq_static
      EXPORT jqTargets
      ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
  endif()

  install(FILES src/jv.h src/jq.h
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

  install(FILES jq.1.prebuilt
    DESTINATION ${CMAKE_INSTALL_MANDIR}/man1
    RENAME jq.1)

  install(FILES README.md NEWS.md COPYING AUTHORS
    DESTINATION ${CMAKE_INSTALL_DOCDIR})

  # libjq.pc generated from libjq.pc.in (uses @prefix@ etc., same vars as
  # autoconf) - configure with @ONLY so only @VAR@ placeholders are touched.
  set(prefix "${CMAKE_INSTALL_PREFIX}")
  set(exec_prefix "\${prefix}")
  set(libdir "\${prefix}/${CMAKE_INSTALL_LIBDIR}")
  set(includedir "\${prefix}/${CMAKE_INSTALL_INCLUDEDIR}")
  set(VERSION "${PROJECT_VERSION}")
  configure_file(libjq.pc.in
    "${CMAKE_CURRENT_BINARY_DIR}/libjq.pc"
    @ONLY)
  install(FILES "${CMAKE_CURRENT_BINARY_DIR}/libjq.pc"
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)
endif()

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------

message(STATUS "")
message(STATUS "jq build configuration:")
message(STATUS "  Version             : ${PROJECT_VERSION}")
message(STATUS "  Shared libjq        : ${JQ_BUILD_SHARED_LIB}")
message(STATUS "  Static libjq        : ${JQ_BUILD_STATIC_LIB}")
message(STATUS "  Oniguruma           : ${JQ_BUILD_ONIGURUMA} (used: ${_jq_use_oniguruma})")
message(STATUS "  decNumber (USE_DECNUM): ${JQ_ENABLE_DECNUM}")
message(STATUS "  pthread             : ${HAVE_PTHREAD}")
message(STATUS "  Tests               : ${JQ_BUILD_TESTS}")
message(STATUS "")
