#!/usr/bin/env bash

set -euo pipefail

input_dir="schemas"
output_dir="src/generated"

use_cfbc=false

function check_dependencies () {
    for bin in flatc rustfmt sed; do
        if [ ! -x "$(which ${bin})" ]; then
            echo "Error: Please check if you have installed ${bin} in your \$PATH."
            echo "    flatc   :   https://github.com/google/flatbuffers"
            echo "    rustfmt :   https://github.com/rust-lang/rustfmt"
            echo "    sed     :   http://www.gnu.org/software/sed"
            if ${use_cfbc}; then
                echo "    cfbc    :   https://github.com/nervosnetwork/cfb"
            fi
            exit 1
        fi
    done
}

function gen_one() {
    local name="$1"
    local flatbuffers="extern crate flatbuffers;"
    echo "Info : Generate rust code for ${name} via flatc."
    flatc -o "${output_dir}" --rust "${input_dir}/${name}.fbs"
    if ${use_cfbc}; then
        flatc -b -o "${output_dir}" --schema "${input_dir}/${name}.fbs"
        cfbc -o "${output_dir}" "${output_dir}/${name}.bfbs"
        rm "${output_dir}/${name}.bfbs"
    fi
    mv "${output_dir}/${name}_generated.rs" "${output_dir}/${name}.rs"
    #mv "${output_dir}/${name}_generated_verifier.rs" "${output_dir}/${name}_verifier.rs"
    echo >> "${output_dir}/mod.rs"
    echo "pub mod ${name};" >> "${output_dir}/mod.rs"
    if ${use_cfbc}; then
        echo "pub mod ${name}_builder;" >> "${output_dir}/mod.rs"
        echo "pub mod ${name}_verifier;" >> "${output_dir}/mod.rs"
    fi
    echo "pub use ${name}::*;" >> "${output_dir}/mod.rs"
    if [ $(grep -c "^include " "${input_dir}/${name}.fbs") -gt 0 ]; then
        echo "Info :     Add 'extern structs' to generated rust code for ${name}."
        grep "^include " "${input_dir}/${name}.fbs" \
                | sed 's/^include "\([a-z]*\).fbs";$/use super::\1::*;/;' \
                | while read extern_use; do
            sed -i "/${flatbuffers}/i\\${extern_use}" "${output_dir}/${name}.rs"
        done
        sed -i "/${flatbuffers}/i\\\n" "${output_dir}/${name}.rs"
    fi
    rustfmt --emit files --quiet "${output_dir}/${name}.rs"
    if ${use_cfbc}; then
        rustfmt --emit files --quiet "${output_dir}/${name}_builder.rs"
        rustfmt --emit files --quiet "${output_dir}/${name}_verifier.rs"
    fi
}

function main() {
    check_dependencies
    if [ ! -d "${output_dir}" ]; then
        mkdir -p "${output_dir}"
    else
        find "${output_dir}" -name "*.rs" -exec rm -v {} \;
    fi
    echo "// automatically generated by a bash script, do not modify

#![allow(clippy::all)]
#![allow(unused_imports)]" >> "${output_dir}/mod.rs"
    find "${input_dir}" -name "*.fbs" -exec basename {} \; \
            | sort | while read fbs_file; do
        local name="${fbs_file%.fbs}"
        gen_one "${name}"
    done
    rustfmt --emit files --quiet "${output_dir}/mod.rs"
}

main "$@"
