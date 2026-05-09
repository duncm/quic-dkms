# Top-level Makefile shipped to /usr/src/quic-<version>/Makefile.
# DKMS invokes this from the build tree (cwd = /var/lib/dkms/quic/<ver>/build/).
#
# It is a thin wrapper around the upstream kbuild Makefile in net/quic/.
# We deliberately only build the production module, quic.ko: by passing
# CONFIG_IP_QUIC=m (and *not* CONFIG_IP_QUIC_TEST), the optional
# quic_unit_test.ko / quic_sample_test.ko targets are skipped.

KERNEL_DIR ?= /lib/modules/$(shell uname -r)/build
ROOTDIR    := $(CURDIR)
MODDIR     := $(ROOTDIR)/net/quic

.PHONY: all modules clean install

all: modules

modules:
	$(MAKE) -C $(KERNEL_DIR) M=$(MODDIR) ROOTDIR=$(ROOTDIR) \
	    CONFIG_IP_QUIC=m modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(MODDIR) clean

# install/uninstall are intentionally not implemented here -- DKMS handles
# placing quic.ko into /lib/modules/<kver>/updates/ and running depmod.
