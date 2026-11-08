#!/bin/sh
# Run the CHECK_KSYMS checks from the pinned upstream configure.ac without
# requiring Autoconf, GnuTLS or the running kernel's headers on DKMS hosts.
set -eu

source_tree=$1
build_tree=$2
configure_ac=$3

test -f "$source_tree/Makefile"
test -f "$build_tree/Module.symvers"

# Keep upstream's basic grep expressions, including backslashes, verbatim.
# Reject changed M4 syntax rather than silently omitting compatibility flags.
checks=$(awk '
    /^[[:space:]]*CHECK_KSYMS\(/ {
        if ($0 !~ /^[[:space:]]*CHECK_KSYMS\(\[[^]]*\], \[[^]]*\], \[[^]]*\], \[[^]]*\]\)[[:space:]]*$/) {
            print "Unsupported CHECK_KSYMS syntax: " $0 > "/dev/stderr"
            exit 1
        }
        split($0, fields, /[][]/)
        print fields[2] "|" fields[4] "|" fields[6] "|" fields[8]
        count++
    }
    END { if (!count) exit 1 }
' "$configure_ac")

printf '%s\n' "$checks" |
while IFS='|' read -r pattern file if_present if_absent; do
    case "$file" in
        Module.symvers) probe_file="$build_tree/$file" ;;
        *) probe_file="$source_tree/$file" ;;
    esac
    # Missing headers indicate an absent feature, as in upstream configure.
    if [ -f "$probe_file" ] && grep -q -- "$pattern" "$probe_file"; then
        commit=$if_present
    else
        commit=$if_absent
    fi
    if [ -n "$commit" ]; then
        printf '%s\n' "-DLINUX_KERNEL_NO_$commit="
    fi
done
