# tools
# ---------------------------------------------------------------------------

V               = @
Q               = $(V:1=)
QUIET_CC        = $(Q:@=@:    '     CC       '$@;)
QUIET_CXX       = $(Q:@=@:    '     CXX      '$@;)
QUIET_IRPY      = $(Q:@=@:    '     IRPY     '$@;)
QUIET_AR        = $(Q:@=@:    '     AR       '$@;)
QUIET_LD        = $(Q:@=@:    '     LD       '$@;)
QUIET_GEN       = $(Q:@=@:    '     GEN      '$@;)
QUIET_CPP       = $(Q:@=@:    '     CPP      '$@;)

MKDIR_P         := mkdir -p
LN_S            := ln -s
UNAME_S         := $(shell uname -s)
TOP             := $(shell echo $${PWD-`pwd`})
HOST_CC         := cc
HOST_CXX        := c++
PY2             := python2
PY3             := python3


ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
$(eval $(ARGS):;@:)

LLVM_CONFIG     := llvm-config
# Homebrew hides llvm here
ifeq ($(shell which $(LLVM_CONFIG) 2> /dev/null),)
LLVM_CONFIG     := /usr/local/opt/llvm/bin/llvm-config
endif
ifeq ($(shell which $(LLVM_CONFIG) 2> /dev/null),)
LLVM_PREFIX     :=
else
LLVM_PREFIX     := "$(shell $(LLVM_CONFIG) --bindir)/"
endif

# clang doesn't support riscv yet; use x86_64 as a placeholder.
LLVM_CC         := $(LLVM_PREFIX)clang -target x86_64-pc-linux-gnu
LLVM_HOST_CC    := $(LLVM_PREFIX)clang
LLVM_LINK       := $(LLVM_PREFIX)llvm-link
LLVM_OBJDUMP    := $(LLVM_PREFIX)llvm-objdump
LLVM_OPT        := $(LLVM_PREFIX)opt

LLVM_CXXFLAGS   = $(shell "$(LLVM_CONFIG)" --cxxflags)
LLVM_LDFLAGS    = $(shell "$(LLVM_CONFIG)" --ldflags)
LLVM_LIBS       = $(shell "$(LLVM_CONFIG)" --libs --system-libs)

# avoid generating memset etc.
LLVM_OPTFLAGS   = -O2 -disable-simplify-libcalls

#ifndef TOOLPREFIX
TOOLPREFIX      := $(shell \
        if which $(ARCH)-unknown-elf-gcc > /dev/null 2>&1; \
        then echo "$(ARCH)-unknown-elf-"; \
        elif which $(ARCH)-linux-gnu-gcc > /dev/null 2>&1; \
        then echo "$(ARCH)-linux-gnu-"; \
		elif which $(ARCH)-suse-linux-gcc > /dev/null 2>&1; \
		then echo "$(ARCH)-suse-linux-"; \
        else \
        echo "error: cannot find gcc for $(ARCH)" 1>&2; exit 1; fi)
#endif


CC              := $(TOOLPREFIX)gcc
CPP             := $(TOOLPREFIX)gcc -E -P
CXX             := $(TOOLPREFIX)g++
LD              := $(TOOLPREFIX)ld
AR              := $(TOOLPREFIX)ar
RANLIB          := $(TOOLPREFIX)ranlib
NM              := $(TOOLPREFIX)nm
OBJCOPY         := $(TOOLPREFIX)objcopy
OBJDUMP         := $(TOOLPREFIX)objdump
GDB             := $(TOOLPREFIX)gdb

ifeq ($(USE_CCACHE),1)
CC              := ccache $(CC)
endif

# files
# ---------------------------------------------------------------------------

# sort object files to make linking deterministic
object          = $(sort $(addprefix $(O)/,$(patsubst %.cc,%.o,$(patsubst %.c,%.o,$(patsubst %.S,%.o,$(patsubst %.s,%.o,$(filter-out %/asm-offsets.c %.lds.S,$(1))))))))


rwildcard       = $(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2) $(filter $(subst *,%,$2),$d))

# ASM offsets
# ---------------------------------------------------------------------------

# Default sed regexp - multiline due to syntax constraints
#
# Use [:space:] because LLVM's integrated assembler inserts <tab> around
# the .ascii directive whereas GCC keeps the <space> as-is.
define sed-offsets
        's:^[[:space:]]*\.ascii[[:space:]]*"\(.*\)".*:\1:; \
        /^->/{s:->#\(.*\):/* \1 */:; \
        s:^->\([^ ]*\) [\$$#]*\([^ ]*\) \(.*\):#define \1 \2 /* \3 */:; \
        s:->::; p;}'
endef

define gen-offsets
        (set -e; \
         echo "/*"; \
         echo " * DO NOT MODIFY."; \
         echo " *"; \
         echo " * This file was automatically generated."; \
         echo " */"; \
         echo ""; \
         echo "#pragma once"; \
         echo ""; \
         sed -ne $(sed-offsets) )
endef

define sed-offsets-rkt
        's:^[[:space:]]*\.ascii[[:space:]]*"\(.*\)".*:\1:; \
        /^->/{s:->#\(.*\):/* \1 */:; \
        s:^->\([^ ]*\) [\$$#]*\([^ ]*\) \(.*\):(define \1 \2) \; \3:; \
        s:->::; p;}'
endef

define gen-offsets-rkt
        (set -e; \
         echo "; DO NOT MODIFY."; \
         echo ";"; \
         echo "; This file was automatically generated."; \
         echo ""; \
         echo "#lang racket"; \
         echo ""; \
         echo "(provide (all-defined-out))"; \
         echo ""; \
         sed -ne $(sed-offsets-rkt) )
endef
