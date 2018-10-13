ifeq ($(PACKAGE_SET),vm)
  ifneq ($(filter $(DISTRIBUTION), debian qubuntu),)
    DEBIAN_BUILD_DIRS := debian
  endif

  RPM_SPEC_FILES := rpm_spec/qubes-tor.spec
endif

# vim: filetype=make
