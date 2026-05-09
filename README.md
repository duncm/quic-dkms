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
├── upstream/             git submodule -> https://github.com/lxin/quic
│                         pinned to a specific upstream commit
├── patches/              local patches applied on top of upstream/
│   ├── series            patches applied in order, '#' = comment
│   └── *.patch
├── debian/               Debian packaging (control, rules, .dkms, ...)
├── dkms/Makefile         Top-level kbuild wrapper installed alongside
│                         the module sources at /usr/src/quic-<ver>/
├── scripts/
│   └── update-version.sh Compute / apply a new package version from
│                         the upstream submodule's HEAD commit
└── README.md
```

## Local patches

The upstream submodule is treated as read-only -- patches that we need
on top of the pinned commit live in `patches/`, listed in
`patches/series` (one filename per line, `-p1` relative to the upstream
tree root, `#` and blank lines ignored).

`debian/rules` stages `upstream/modules/` into `debian/_stage/`, applies
each patch with `patch -p1`, and only then installs the (now patched)
sources into `/usr/src/quic-<version>/`. Nothing is mutated in
`upstream/` itself.

To add a new patch:

```sh
cp -a upstream/modules /tmp/work/modules
# edit /tmp/work/modules/...
diff -ruN upstream/modules /tmp/work/modules \
    | sed 's,^--- upstream/,--- a/,;s,^+++ /tmp/work/,+++ b/,' \
    > patches/0002-my-fix.patch
echo 0002-my-fix.patch >> patches/series
```

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
sudo apt install -y devscripts debhelper dh-dkms rsync xz-utils
git submodule update --init --recursive

# Produce ../quic-dkms_<upstream-version>.orig.tar.xz from the working
# tree. This is required for 3.0 (quilt) builds; rerun after every
# changelog/version bump.
scripts/make-orig.sh

dpkg-buildpackage -b -us -uc
```

The result, `../quic-dkms_<version>_all.deb`, can be installed on any
Trixie system that has the matching `linux-headers-*` package.

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
