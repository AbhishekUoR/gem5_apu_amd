#
# Copyright © 1997,2000 Paul D. Smith
# Verbatim copying and distribution is permitted in any medium, provided this
# notice is preserved.
# See http://make.paulandlesley.org/multi-arch.html#advanced
#

# Figure out absolute path to where this makefile lives, since it's
# where all the other included makefiles live too.  This always seems
# to come out with a trailing slash.
CLBMDIR = $(dir $(abspath $(lastword  $(MAKEFILE_LIST))))

TGTDIRS = 64b 32b dbg64b dbg32b

NEWGOALS = $(filter-out $(TGTDIRS), $(MAKECMDGOALS))

.SUFFIXES:

MAKETARGET = $(MAKE) --no-print-directory -C $@ -f $(CLBMDIR)program.mk \
                 CLBMDIR=$(CLBMDIR) SRCDIR=$(CURDIR) $(NEWGOALS)

.PHONY: $(TGTDIRS)
$(TGTDIRS):
	+@echo "Building in $@"
	+@[ -d $@ ] || mkdir -p $@
	+@$(MAKETARGET)

Makefile : ;
%.mk :: ;

% :: $(TGTDIRS) ;

.PHONY: clean
clean:
	rm -rf $(TGTDIRS)
