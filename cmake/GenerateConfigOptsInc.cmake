# GenerateConfigOptsInc.cmake
#
# Produce src/config_opts.inc that defines JQ_CONFIG to a single string
# describing how the build was configured. The autotools rule pulls this
# from `config.status --config`. For CMake builds we synthesize a similar
# string from the active CMake options.
#
# Required input variables:
#   OUTPUT  - path of the .inc file to produce
#   OPTS    - configuration string to embed in JQ_CONFIG

if(NOT DEFINED OUTPUT OR NOT DEFINED OPTS)
  message(FATAL_ERROR "GenerateConfigOptsInc.cmake: OUTPUT and OPTS must be set")
endif()

# Escape backslashes and double quotes the same way the autotools sed
# pipeline does.
string(REPLACE "\\" "\\\\" escaped "${OPTS}")
string(REPLACE "\"" "\\\"" escaped "${escaped}")

file(WRITE "${OUTPUT}" "#define JQ_CONFIG \"${escaped}\"\n")
