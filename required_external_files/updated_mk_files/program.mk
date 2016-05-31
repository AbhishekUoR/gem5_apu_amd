#
# The benchmark-specific makefile should define the following before
# including this file:
#   OBJECTS EXE KERNELS KERNEL_FLAGS

TGTDIR = $(notdir $(CURDIR))

# Find the top of the HSA repo tree, right above this one
HSADIR = $(abspath $(CLBMDIR)..)

# Configure which binary we're building based on the target directory name
ifeq (64, $(findstring 64, $(TGTDIR)))
    BITS := 64
else ifeq (32, $(findstring 32, $(TGTDIR)))
    BITS := 32
else
    $(error Target directory name does not indicate BITS)
endif

ifeq (dbg, $(findstring dbg, $(TGTDIR)))
    MODE := dbg
else
    MODE :=
endif

# Since we're building in a different directory than SRCDIR, we use
# vpath to find the sources. Note that we can't use a blanket VPATH
# because that messes up the rules that create the build subdirectories
# (since the same subdirectories are already found under SRCDIR).
vpath %.c $(SRCDIR)
vpath %.cpp $(SRCDIR)
vpath %.h $(SRCDIR)
vpath %.cl $(SRCDIR)

# This makes sure that 'all' is still the default even if rules get
# defined in include.mk
.PHONY: default
default: all

# Now include the rules specific to the particular benchmark
include $(SRCDIR)/include.mk

################      KERNEL COMPILATION CONFIGURATION START     #############

CLC_FLAGS       = --enable-hsail-extensions --cl-std=CL2.0 ${KERNEL_FLAGS}
OPT_FLAGS       = -O3 -gpu -whole -verify
LLC_FLAGS       = -filetype=obj -hsail-enable-gcn=0
HOF_FLAGS       = -target=8:0:1 -model=large -O2 -dump-isa

# Kernel Compilation: Common
HSA_TOOLS       ?= /home/scratch/massem/research/software/CLOC-master
PATH            := ${HSA_TOOLS}/bin:${PATH}
LD_LIBRARY_PATH := ${HSA_TOOLS}/bin:${LD_LIBRARY_PATH}
BUILTINS_HSAIL  ?= ${HSA_TOOLS}/bin/builtins-hsail.bc
CLC             := clc2
CLC_FLAGS       += -I$(HSA_TOOLS)
LLVM-AS         := llvm-as
LLVM-LINK       := llvm-link
LLVM-DIS        := llvm-dis
OPT             := opt
LLC             := llc
HSAILASM        := hsailasm
HOF             := amdhsafin

# This will leave all intermediate files as well. Comment it out if
# they are not needed.
.SECONDARY:

################      KERNEL COMPILATION CONFIGURATION END      ##############

HSA_RUNTIME     ?= $(HSADIR)/hsa-runtime
OPENCL_RUNTIME  ?= $(HSADIR)/cl-runtime
M5_UTIL         ?= $(HSADIR)/util/m5

CPPFLAGS        += -I$(SRCDIR) -I$(OPENCL_RUNTIME) -I $(HSA_RUNTIME)/inc\
                   -I$(M5_UTIL)


# Link with either the Emulated CL-Runtime or the stock HSA Runtime
ifeq ($(HSA_APP), 1)
    LIB += $(HSA_RUNTIME)/core/debug64/libhsa-runtime64.so
    LIB += $(HSA_RUNTIME)/libhsakmt/build/lnx64a/libhsakmt.so
else
    LIB += $(OPENCL_RUNTIME)/$(MODE)$(BITS)b/libOpenCL.a
    LIB += $(M5_UTIL)/m5op_x86.o
    LIB += $(MASSEM_DEPENDENCIES)/zlib-1.2.8/lib/libz.a
    LDFLAGS = -static
endif

ifeq ($(BITS), 64)
    CLC_FLAGS +=
    LLC_FLAGS += -march=hsail-64
else
    CFLAGS += -m32
    LLC_FLAGS += -march=hsail
endif

CXXFLAGS = $(CFLAGS)

ifndef NO_FINALIZER
all: $(EXE) brig hsail isa cp_kernels
else
all: $(EXE) brig hsail cp_kernels
endif

$(EXE): $(OBJECTS) $(LIB)
	#$(LINK.cc) -o $@ $^ -lz
	$(LINK.cc) -o $@ $^

# This section creates dependencies and rules to automate the creation
# of build subdirectories as needed based on OBJECTS and KERNELS. If
# we don't do this, then the compiler will fail with "can't create
# output file, directory does not exist" type errors.

# Since files in KERNELS don't have an extension (while files in
# OBJECTS end in .o), we need to provide the extension of the first
# file derived from the .cl file for this to work
DIRLIST = $(OBJECTS) $(foreach k,$(KERNELS),$(k).ll)

# This macro creates an "order-only" dependency between an object and
# its directory.  We'll generate one of these for each object.
define mkdir-dep
$(1): | $(dir $(1))
endef

$(foreach obj,$(DIRLIST),$(eval $(call mkdir-dep,$(obj))))

# This macro creates a rule to create each directory. We have to do
# this exactly once per directory, else make complains about having
# multiple rules for the same target.
define mkdir-rule
$(dir $(1)):
	mkdir -p $(dir $(1))
endef

# The built-in sort filters out duplicates (like 'sort -u' in the
# shell). We don't actually care about sorting.
$(foreach d,$(sort $(dir $(DIRLIST))),$(eval $(call mkdir-rule,$(d))))

################      KERNEL COMPILATION RULES START      ##################

cp_kernels : $(foreach k,$(KERNELS),$(k))

hsail : $(foreach k,$(KERNELS),$(k).hsail)

brig : $(foreach k,$(KERNELS),$(k).brig)

isa : $(foreach k,$(KERNELS),$(k).isa)

% : %.cl
	cp $(SRCDIR)/$@.cl $(SRCDIR)/$(TGTDIR)

# Converts kernel code to text llvm-ir
# Rule for making *.ll: compile them from *.cl using clc2

# Convert text form of llvm-ir to bitcode
# Rule for making .fe.bc: simply copy .cl and change extention
%.fe.bc : %.cl
		$(CLC) $(CLC_FLAGS) -o $@ $^

%.fe.ll : %.fe.bc
		$(LLVM-DIS) $*.fe.bc -o $*.tmp.ll
		cp $*.tmp.ll $*.opt.ll

# Link builtin .bc with kernel .bc
# Rule for making *.linked.bc: link *.bc using llvm
%.linked.bc : %.fe.bc
		$(LLVM-LINK) $*.fe.bc -l $(BUILTINS_HSAIL) -o $*.linked.bc

# Rule for making *.linked.ll: disassemble from *.linked.bc using llvm
%.linked.ll : %.linked.bc
		$(LLVM-DIS) $*.linked.bc -o $*.linked.ll

# Transform bitcode to prepass
# Rule for making *.tmp.bc: make *.tmp.bc using opt
%.opt.bc : %.linked.bc
		$(OPT) $(OPT_FLAGS) $*.linked.bc -o $*.opt.bc

# Convert bitcode form of llvm-ir to readable form
# Rule for making *.opt.ll: disassemble from *.tmp.ll using llvm
%.opt.ll : %.opt.bc
		$(LLVM-DIS) $*.opt.bc -o $*.tmp.ll
		cp $*.tmp.ll $*.opt.ll

# Generate BRIG
# Rule for making *.brig : compile from *.tmp.bc using llc
%.brig : %.opt.bc
		$(LLC) $(LLC_FLAGS) -o $*.brig $*.opt.bc

# Generate ISA
# Rule for making *.isa : finalize from *.hsail using amdhsafin
%.isa : %.hsail
	    $(HOF) $(HOF_FLAGS) -output=$*.isa -hsail $*.hsail
	    mv amdhsa001.isa amdhsa001.isa.txt

# Disassemble from BRIG to HSAIL
# Rule for making *.hsail : disassemble from *.brig using hsailasm
%.hsail : %.brig
		#$(HSAILASM) -disassemble -o=$*.hsail $*.brig
		$(HSAILASM) -disassemble -o $*.hsail $*.brig

################        KERNEL COMPILATION RULES END      ##################
