# GenerateBuiltinInc.cmake
#
# Convert a jq builtin source file into a comma-separated list of octal
# byte literals suitable for inclusion in a C array initializer.
#
# This is the portable CMake equivalent of the `od ... | sed ...` pipeline
# used by Makefile.am.
#
# Required input variables:
#   INPUT  - path to the source builtin.jq file
#   OUTPUT - path to the .inc file to produce

if(NOT DEFINED INPUT OR NOT DEFINED OUTPUT)
  message(FATAL_ERROR "GenerateBuiltinInc.cmake: INPUT and OUTPUT must be set")
endif()

file(READ "${INPUT}" hex HEX)
string(LENGTH "${hex}" hex_len)
math(EXPR num_bytes "${hex_len} / 2")

set(parts "")
set(i 0)
while(i LESS hex_len)
  string(SUBSTRING "${hex}" ${i} 2 byte)
  # Convert two hex chars to a decimal value, then format as 3-digit octal
  # to match the original `od -t o1` zero-padded octal output.
  math(EXPR dec "0x${byte}")
  # Format as 3-digit zero-padded octal (e.g. 007, 052, 377)
  math(EXPR o1 "${dec} / 64")
  math(EXPR o2 "(${dec} / 8) % 8")
  math(EXPR o3 "${dec} % 8")
  list(APPEND parts " 0${o1}${o2}${o3}")
  math(EXPR i "${i} + 2")
endwhile()

string(REPLACE ";" "," joined "${parts}")
# Match the autotools sed pipeline, which leaves a trailing comma on the
# very last byte. The C source appends a literal '\0' element after the
# include so a trailing comma here is required.
file(WRITE "${OUTPUT}" "${joined},\n")
