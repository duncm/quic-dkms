# quic-dkms

A DKMS source package for the [lxin/quic](https://github.com/lxin/quic)
in-kernel QUIC implementation, packaged as a Debian `.deb`.

The package builds and installs only the production `quic.ko` module; it
does not install any user-space headers, the `libquic` user-space
library, or the upstream test modules.

Initial target: **Debian Trixie / arm64** (the package itself is
`Architecture: all`; DKMS rebuilds the module on the user's system).

## Layout

```
quic-dkms/
├── upstream/                git submodule -> https://github.com/lxin/quic
│                            pinned to a specific upstream commit
├── debian/
│   ├── patches/             local patches applied on top of upstream/
│   │   ├── series           patches applied in order, '#' = comment
│   │   └── *.patch          paths relative to the package root
│   │                        (e.g. upstream/modules/net/quic/socket.c)
│   ├── source/{format,options}
│   ├── rules                debhelper sequence + DKMS install
│   └── ... (control, copyright, changelog, quic-dkms.dkms)
├── dkms/Makefile            Top-level kbuild wrapper installed alongside
│                            the module sources at /usr/src/quic-<ver>/
├── scripts/
│   ├── update-version.sh    Compute / apply a new package version from
│   │                        the upstream submodule's HEAD commit
│   └── make-orig.sh         Produce the .orig.tar.xz from the working tree
├── .github/workflows/       CI: build amd64 + arm64 .debs and ship them
│                            to a GitHub Release on every push to main
└── README.md
```

## Local patches

The upstream submodule is treated as read-only at rest -- any patches
we carry on top of the pinned commit live in `debian/patches/`, listed
in `debian/patches/series` (one filename per line, `#` and blank lines
ignored). Paths inside each patch are relative to the *package root*
(`a/upstream/modules/...`, `b/upstream/modules/...`), and they apply
with `patch -p1`.

At the moment `debian/patches/series` is empty -- the pinned upstream
commit builds unmodified against every kernel we target. The layout
below is kept documented so patches can be re-added when they're
needed.

This is the standard `3.0 (quilt)` layout, so:

* `dpkg-source --before-build` (run automatically by `dpkg-buildpackage`)
  applies every patch in `series` to the working tree before
  `debian/rules` runs.
* `debian/rules` then just copies the already-patched
  `upstream/modules/...` into the DKMS source tree at
  `/usr/src/quic-<upstream-version>/`.
* `dpkg-source --after-build` un-applies the patches (we set
  `unapply-patches` in `debian/source/options`), so the `upstream/`
  submodule is left clean after every build.

To add a new patch:

```sh
# Bring upstream/ up to date.
git submodule update --init upstream

# Apply existing patches and start a quilt-managed new patch on top.
QUILT_PATCHES=debian/patches quilt push -a
QUILT_PATCHES=debian/patches quilt new 0002-my-fix.patch
QUILT_PATCHES=debian/patches quilt add upstream/modules/net/quic/<file>
# edit upstream/modules/net/quic/<file>
QUILT_PATCHES=debian/patches quilt refresh
QUILT_PATCHES=debian/patches quilt pop -a   # leave upstream/ clean again
```

(`apt install quilt` if needed.)

## Versioning

Package versions follow:

```
0~YYYYmmdd.NNNN.git+<short-hash>-<revision>
```

* `0~` — fixed leading marker. The `~` makes the whole version sort
  *before* any future "real" upstream 0.x release in dpkg's ordering, so
  `0~20260507....` < `0` < `0.1` etc.
* `YYYYmmdd` — committer date (UTC) of the pinned upstream commit
* `NNNN` — 4-digit zero-padded snapshot counter (0000–9999), bumped by
  the maintainer when shipping a different snapshot of the same calendar
  day
* `<short-hash>` — `git log -1 --format=%h` of the pinned commit
* `<revision>` — Debian package revision counter, starting at `1`,
  bumped for packaging-only changes against the same upstream commit

Example: `0~20260507.0000.git+70ceda0-1`. The everything-before-the-last
hyphen part (here `0~20260507.0000.git+70ceda0`) is the upstream version,
and is what ends up in `/usr/src/quic-<upstream-version>/`. The trailing
`-<revision>` is the Debian revision and is *not* included in the DKMS
source dir name, so bumping it does not duplicate the on-disk source
tree.

This is a Debian *quilt* package (`debian/source/format` = `3.0 (quilt)`),
so building requires both the Debian tree and a separately-generated
`.orig.tar.xz` (see "Building the .deb" below).

To bump to a new upstream commit:

```sh
git -C upstream fetch origin
git -C upstream checkout <new-commit-or-tag>
git add upstream
# default counter=0, revision=1; pass --counter / --revision to override
scripts/update-version.sh --update --message "..."
git commit -am "Bump upstream to <short-hash>"
```

## Building the .deb

From the repo root, on Debian Trixie:

```sh
sudo apt install -y devscripts debhelper dh-dkms quilt rsync xz-utils
git submodule update --init --recursive

# Produce ../quic-dkms_<upstream-version>.orig.tar.xz from the working
# tree. This is required for 3.0 (quilt) builds; rerun after every
# changelog/version bump.
scripts/make-orig.sh

# Binary only:
dpkg-buildpackage -b -us -uc
# Or full set (binary + .dsc / .debian.tar.xz / *_source.changes):
dpkg-buildpackage -us -uc
```

The result, `../quic-dkms_<version>_all.deb`, can be installed on any
Trixie system that has the matching `linux-headers-*` package.

A GitHub Actions workflow at `.github/workflows/build-and-release.yml`
performs this build on both amd64 and arm64 GitHub-hosted runners on
every push to `main`. In parallel, it also runs the upstream test
suite (`upstream/tests/runtest.sh`) on each architecture: the test
modules (`quic_sample_test.ko`) and user-space test binaries
(`func_test`, `perf_test`, `alpn_test`, `ticket_test`, `sample_test`)
are built from the patched upstream tree on the bare runner and the
full suite is exercised against the runner's live kernel. The HTTP/3
sub-suite is auto-skipped (no `libnghttp3-dev` installed in CI; it
otherwise reaches out to ~14 public websites and is too flaky for
CI), and the tlshd sub-suite is auto-skipped on runners without an
active `tlshd` daemon. Releases only publish if both the build and
the test jobs succeed on both architectures. None of these test
modules end up in the published `.deb` -- the DKMS source tree
installed by the package builds with `CONFIG_IP_QUIC=m` only, so
users only ever get `quic.ko`.

## Installing / using the module

```sh
sudo apt install -y dkms linux-headers-arm64
sudo dpkg -i ../quic-dkms_<version>_all.deb
sudo modprobe quic
```

DKMS will automatically rebuild `quic.ko` for every kernel that has
matching headers installed. The module is placed in
`/lib/modules/<kver>/updates/quic.ko`.

## Build details

DKMS invokes the wrapper at `/usr/src/quic-<ver>/Makefile`, which calls
the upstream kbuild `Makefile` in `net/quic/` with `CONFIG_IP_QUIC=m`.
Because `CONFIG_IP_QUIC_TEST` is intentionally left undefined, the
upstream test modules (`quic_unit_test.ko`, `quic_sample_test.ko`) are
*not* built.

## Licensing

The upstream module sources are GPL-2.0-or-later (see
`upstream/COPYING`); the Debian packaging in this repo is also
GPL-2.0-or-later. See `debian/copyright` for the full picture.
