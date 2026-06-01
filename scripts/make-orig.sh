#!/usr/bin/env bash
# Build the .orig.tar.xz expected by dpkg-source for a 3.0 (quilt)
# package.
#
# The tarball contains the entire repo working tree EXCEPT:
#   - debian/                           (lives in the .debian.tar.xz)
#   - .git, .gitmodules, .gitignore     (Git infrastructure)
#   - .pc/                              (quilt state, only present mid-build)
#   - the upstream submodule's own .git pointer
#
# The tarball ends up one directory above the repo root, named
#   <source-package>_<upstream-version>.orig.tar.xz
# matching what dpkg-source expects.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -f debian/changelog ]]; then
    echo "error: debian/changelog not found (cwd: $(pwd))" >&2
    exit 1
fi

if [[ ! -d upstream/modules || -z "$(ls -A upstream/modules 2>/dev/null)" ]]; then
    echo "error: upstream submodule appears empty;" >&2
    echo "       run 'git submodule update --init upstream' first." >&2
    exit 1
fi

source_pkg=$(dpkg-parsechangelog -SSource)
full_version=$(dpkg-parsechangelog -SVersion)
upstream_version=${full_version%-*}    # strip trailing "-<rev>"

orig_file="${source_pkg}_${upstream_version}.orig.tar.xz"
orig_dir="${source_pkg}-${upstream_version}"

if [[ -e "../${orig_file}" ]]; then
    echo "../${orig_file} already exists; remove it first if you want to regenerate."
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT

# Copy the whole tree using rsync, with the necessary excludes. We use
# rsync (rather than tar's --exclude) so the same exclusion list works
# from any CWD and so the upstream submodule contents are followed
# transparently as plain files/directories.
rsync -a \
    --exclude='/debian' \
    --exclude='/debian/' \
    --exclude='/debian/**' \
    --exclude='.git' \
    --exclude='.gitmodules' \
    --exclude='.gitignore' \
    --exclude='/.pc' \
    --exclude='/.pc/**' \
    --exclude='*.deb' \
    --exclude='*.changes' \
    --exclude='*.buildinfo' \
    --exclude='*.dsc' \
    --exclude='*.tar.*' \
    "${REPO_ROOT}/" "${tmp}/${orig_dir}/"

# Reproducible-ish tarball: sorted file list, fixed mtime, no owner.
mtime=$(date -u -d "@$(git -C upstream log -1 --format=%ct)" '+%Y-%m-%d %H:%M:%SZ' \
        2>/dev/null || date -u '+%Y-%m-%d %H:%M:%SZ')
tar --create \
    --xz \
    --sort=name \
    --mtime="${mtime}" \
    --owner=0 --group=0 --numeric-owner \
    --file "../${orig_file}" \
    -C "${tmp}" \
    "${orig_dir}"

echo "Created ../${orig_file}"
