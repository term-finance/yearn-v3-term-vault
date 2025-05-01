#!/usr/bin/env bash
#
# Run `forge flatten` on all .sol files recursively in the contracts/ directory and deps
# and store the output in the flattened/ directory. Also create all parent directories
# before writing the output if they don't exist.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
usage="Usage: $0"

set -o errexit

# Ensure the contracts/ directory exists.
outputs_dir="${script_dir}/out"
if [ ! -d "${outputs_dir}" ]; then
  echo "The out/ directory does not exist. ${usage}"
  exit 1
fi

# Ensure the flattened/ directory exists.
flattened_dir="${script_dir}/flattened"
mkdir -p "${flattened_dir}"

# Flatten all .sol files in the contracts/ directory.
find "${outputs_dir}" -type f -path "*.sol/*.json" -print0 | while IFS= read -r -d $'\0' file; do
  # Check that the path .metadata.settings.compilationTarget exists in the json file
  if ! jq -e '.metadata.settings.compilationTarget' "${file}" > /dev/null 2>&1; then
    echo "The path .metadata.settings.compilationTarget does not exist in ${file}. Skipping."
  else
    # Read the compilation target from the json file
    compilation_target=$(jq -r '.metadata.settings.compilationTarget | keys | .[0]' "${file}")
    # Skip scripts (paths that begin with script/)
    if [[ "${compilation_target}" == *"script/"* ]]; then
      echo "Skipping script file ${file}."
      continue
    fi
    # Skip test files (paths that begin with src/test/)
    if [[ "${compilation_target}" == *"src/test/"* ]]; then
      echo "Skipping test file ${file}."
      continue
    fi
    # If the compilation target does not exist as a file, skip it
    if [ ! -f "${script_dir}/${compilation_target}" ]; then
      echo "The compilation target ${compilation_target} does not exist. Skipping."
      continue
    fi
    # Get the filename component of the compilation target path
    output_name=$(basename "${compilation_target}")
    # Generate sources for the compilation target using forge flatten
    echo "Flattening ${file} (${compilation_target}) to ${flattened_dir}/${output_name}..."
    forge flatten "${script_dir}/${compilation_target}" > "${flattened_dir}/${output_name}"
  fi
done
