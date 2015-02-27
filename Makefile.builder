ifeq ($(PACKAGE_SET),vm)
  ifneq ($(filter $(DISTRIBUTION), debian qubuntu),)
    DEBIAN_BUILD_DIRS := debian
    SOURCE_COPY_IN := source-debian-quilt-copy-in
  endif

  RPM_SPEC_FILES := rpm_spec/qubes-tor.spec
endif

source-debian-quilt-copy-in: PARSER = $(PWD)/scripts-debian/debian-parser
source-debian-quilt-copy-in: VERSION = $(shell $(PARSER) changelog --package-version $(ORIG_SRC)/$(DEBIAN_BUILD_DIRS)/changelog)
source-debian-quilt-copy-in: NAME = $(shell $(PARSER) changelog --package-name $(ORIG_SRC)/$(DEBIAN_BUILD_DIRS)/changelog)
source-debian-quilt-copy-in: ORIG_FILE = "$(CHROOT_DIR)/$(DIST_SRC)/../$(NAME)_$(VERSION).orig.tar.gz"
source-debian-quilt-copy-in:
	-$(shell $(ORIG_SRC)/debian-quilt $(ORIG_SRC)/series-debian-vm.conf $(CHROOT_DIR)/$(DIST_SRC)/debian/patches)
	tar cfz $(ORIG_FILE) --exclude-vcs --exclude=rpm --exclude=pkgs --exclude=deb --exclude=debian -C $(CHROOT_DIR)/$(DIST_SRC) .

# vim: filetype=make
