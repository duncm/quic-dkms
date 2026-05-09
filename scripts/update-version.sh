#!/usr/bin/env bash
# Compute (and optionally apply) the quic-dkms package version derived
# from the upstream submodule's currently-checked-out commit.
#
# Version format:
#     0~YYYYmmdd.NNNN.git+<short-hash>-<revision>
# where:
#     0~          fixed leading marker so the version sorts before any
#                 future "real" 0.x release of upstream,
#     YYYYmmdd    upstream commit's committer date in UTC, no separators,
#     NNNN        4-digit zero-padded snapshot counter (default 0000),
#                 used to disambiguate multiple snapshots of the same
#                 calendar day,
#     <short>     upstream commit's short hash,
#     <revision>  Debian package revision counter (default 1), bumped
#                 by the maintainer when re-releasing the same upstream
#                 commit with packaging-only changes.
#
# Usage:
#     scripts/update-version.sh                # print version (default
#                                              # counter=0, revision=1)
#     scripts/update-version.sh --counter 1    # use NNNN=0001
#     scripts/update-version.sh --revision 2   # use -2 revision
#     scripts/update-version.sh --upstream     # print upstream version
#                                              # only (no '-<revision>')
#     scripts/update-version.sh --update       # also write a new
#                                              # debian/changelog entry
#                                              # via dch(1)
#     scripts/update-version.sh --update --revision 2 --message "..."

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="${REPO_ROOT}/upstream"

counter=0
revision=1
do_update=0
upstream_only=0
message=""

while (($#)); do
    case "$1" in
        --counter)
            counter="$2"
            shift 2
            ;;
        --counter=*)
            counter="${1#*=}"
            shift
            ;;
        --revision)
            revision="$2"
            shift 2
            ;;
        --revision=*)
            revision="${1#*=}"
            shift
            ;;
        --update)
            do_update=1
            shift
            ;;
        --upstream)
            upstream_only=1
            shift
            ;;
        --message)
            message="$2"
            shift 2
            ;;
        --message=*)
            message="${1#*=}"
            shift
            ;;
        -h|--help)
            sed -n '2,32p' "$0"
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 64
            ;;
    esac
done

if [[ ! -d "${UPSTREAM_DIR}/.git" && ! -f "${UPSTREAM_DIR}/.git" ]]; then
    echo "error: upstream submodule not initialised at ${UPSTREAM_DIR}" >&2
    echo "       run: git submodule update --init upstream" >&2
    exit 1
fi

if ! [[ "${counter}" =~ ^[0-9]+$ ]] || ((counter < 0 || counter > 9999)); then
    echo "error: --counter must be an integer between 0 and 9999" >&2
    exit 64
fi
if ! [[ "${revision}" =~ ^[0-9]+$ ]] || ((revision < 1)); then
    echo "error: --revision must be a positive integer (>= 1)" >&2
    exit 64
fi
counter_str=$(printf '%04d' "${counter}")

# Use committer-date in UTC so the version is reproducible regardless of
# the local timezone of whoever invokes this script.
commit_date=$(TZ=UTC git -C "${UPSTREAM_DIR}" log -1 --format='%cd' --date=format-local:'%Y%m%d')
short_hash=$(git -C "${UPSTREAM_DIR}" log -1 --format='%h')
full_hash=$(git -C "${UPSTREAM_DIR}" log -1 --format='%H')
subject=$(git -C "${UPSTREAM_DIR}" log -1 --format='%s')

upstream_version="0~${commit_date}.${counter_str}.git+${short_hash}"
full_version="${upstream_version}-${revision}"

if ((upstream_only)); then
    echo "${upstream_version}"
else
    echo "${full_version}"
fi

if ((do_update)); then
    cd "${REPO_ROOT}"
    if [[ -z "${message}" ]]; then
        message="Update upstream to ${short_hash} (\"${subject}\")."
    fi
    DEBEMAIL="${DEBEMAIL:-$(git config user.email)}" \
    DEBFULLNAME="${DEBFULLNAME:-$(git config user.name)}" \
        dch --newversion "${full_version}" --distribution trixie --force-distribution -- "${message}"
    echo "Updated debian/changelog -> ${full_version}"
    echo "Upstream pinned at: ${full_hash}"
fi
