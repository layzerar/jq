# GenerateVersionH.cmake
#
# Generate src/version.h with a JQ_VERSION macro. Mirrors the autotools
# rule, which prefers the output of scripts/version (git describe) and
# falls back to the configure-time VERSION value.
#
# Required input variables:
#   SOURCE_DIR - top-level project source directory
#   OUTPUT     - path of version.h to produce
#   FALLBACK   - fallback version string when git is unavailable

if(NOT DEFINED SOURCE_DIR OR NOT DEFINED OUTPUT OR NOT DEFINED FALLBACK)
  message(FATAL_ERROR "GenerateVersionH.cmake: SOURCE_DIR, OUTPUT and FALLBACK must be set")
endif()

set(version "")

# Try scripts/version first; it requires a real git checkout.
if(EXISTS "${SOURCE_DIR}/.git" AND EXISTS "${SOURCE_DIR}/scripts/version")
  find_program(SH_EXECUTABLE NAMES sh)
  if(SH_EXECUTABLE)
    execute_process(
      COMMAND "${SH_EXECUTABLE}" "${SOURCE_DIR}/scripts/version"
      WORKING_DIRECTORY "${SOURCE_DIR}"
      OUTPUT_VARIABLE version
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_QUIET
      RESULT_VARIABLE _rv)
    if(NOT _rv EQUAL 0)
      set(version "")
    endif()
  endif()
endif()

if(NOT version)
  set(version "${FALLBACK}")
endif()

set(new_content "#define JQ_VERSION \"${version}\"\n")

# Only rewrite the file when its contents change, so dependent objects
# don't get rebuilt unnecessarily.
set(old_content "")
if(EXISTS "${OUTPUT}")
  file(READ "${OUTPUT}" old_content)
endif()

if(NOT "${old_content}" STREQUAL "${new_content}")
  file(WRITE "${OUTPUT}" "${new_content}")
endif()
