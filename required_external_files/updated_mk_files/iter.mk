# This makefile lets us iterate over all the subdirectories in a
# directory and make one of a set of particular predefined targets in
# each subdirectory.  This works recursively if an appropriate
# Makefile is defined in each subdirectory.
#
# The SUBDIRS variable must be set before including this file to
# define the subdirectories.

TARGETS = all clean 32b 64b dbg32b dbg64b

.PHONY: $(TARGETS) default

# change this line to change the default action
# (using one of the targets above)
default: 64b

define do-target
$(1): $$(foreach subdir, $$(SUBDIRS), $(1)-$$(subdir))

$(1)-%:
	$$(MAKE) -C $$* $(1)
endef

$(foreach tgt, $(TARGETS), $(eval $(call do-target,$(tgt))))
