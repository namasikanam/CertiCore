include config.mk
include tools/lib.mk
include tools/function.mk

PROJ	:= lab2
EMPTY	:=
SPACE	:= $(EMPTY) $(EMPTY)
SLASH	:= /

# eliminate default suffix rules
.SUFFIXES: .c .S .h

# delete target files if there is an error (or make is interrupted)
.DELETE_ON_ERROR:

ifeq ($(MAKECMDGOALS),verify)
IS_VERIF = TRUE
endif

ifdef IS_VERIF
CONFIG_CFLAGS += -DIS_VERIF=$(IS_VERIF)
endif

# no built-in rules and variables
MAKEFLAGS       += --no-builtin-rules --no-builtin-variables

BASE_CFLAGS     := -ffreestanding
BASE_CFLAGS     += -fno-stack-protector
BASE_CFLAGS     += -fno-strict-aliasing
# make it simpler for symbolic execution to track PC
BASE_CFLAGS     += -fno-jump-tables
# no unaligned memory accesses
BASE_CFLAGS     += -mstrict-align
BASE_CFLAGS     += -g -O$(OLEVEL)
BASE_CFLAGS     += -Wall -Wno-unused
BASE_CFLAGS     += -Werror

CFLAGS     := $(BASE_CFLAGS) $(CONFIG_CFLAGS)
CFLAGS     += -mcmodel=medany
CFLAGS     += -mabi=lp64
CFLAGS     += -ffunction-sections -fdata-sections
CFLAGS     += -fno-PIE
CFLAGS     += -march=rv64ima
CFLAGS     += -std=gnu11
CFLAGS     += -nostdinc
CFLAGS     += $(DEFS)

CTYPE	:= c S
LTYPE   := c

LDFLAGS	:= -m elf64lriscv
LDFLAGS	+= -nostdlib --gc-sections

UBSAN_CFLAGS := -fsanitize=integer-divide-by-zero
UBSAN_CFLAGS += -fsanitize=shift
UBSAN_CFLAGS += -fsanitize=signed-integer-overflow

COPY	:= cp
MKDIR   := mkdir -p
MV		:= mv
RM		:= rm -f
AWK		:= awk
SED		:= sed
SH		:= sh
TR		:= tr
TOUCH	:= touch -c

OBJDIR	:= obj
BINDIR	:= bin

ALLOBJS	:=
ALLDEPS	:=
TARGETS	:=

include racket/racket.mk

listf_cc = $(call listf,$(1),$(CTYPE))
listf_ll = $(call listf, $(1), $(LTYPE))

# for cc
add_files_cc = $(call add_files,$(1),$(CC),$(CFLAGS) $(3),$(2),$(4))

cgtype = $(patsubst %.$(2),%.$(3),$(1))
asmfile = $(call cgtype,$(call toobj,$(1)),o,asm)
mapfile = $(call cgtype,$(call toobj,$(1)),o,map)
mapracket = $(call cgtype,$(call toobj,$(1)),o,map.rkt)
asmracket = $(call cgtype,$(call toobj,$(1)),o,asm.rkt)
globalfile = $(call cgtype,$(call toobj,$(1)),o,global.rkt)

# for match pattern
match = $(shell echo $(2) | $(AWK) '{for(i=1;i<=NF;i++){if(match("$(1)","^"$$(i)"$$")){exit 1;}}}'; echo $$?)

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
# include kernel/user

INCLUDE	+= libs/

CFLAGS	+= $(addprefix -I,$(INCLUDE))
LLVM_IFLAGS += $(addprefix -I,$(INCLUDE))

LIBDIR	+= libs

$(call add_files_cc,$(call listf_cc,$(LIBDIR)),libs,)

# -------------------------------------------------------------------
# kernel

KINCLUDE	+= kern/debug/ \
			   kern/driver/ \
			   kern/trap/ \
			   kern/mm/ \
			   kern/arch/

KSRCDIR		+= kern/init \
			   kern/libs \
			   kern/debug \
			   kern/driver \
			   kern/trap \
			   kern/mm

KCFLAGS		+= $(addprefix -I,$(KINCLUDE))
LLVM_IFLAGS += $(addprefix -I,$(KINCLUDE))

$(call add_files_cc,$(call listf_cc,$(KSRCDIR)),kernel,$(KCFLAGS))

# create kernel target
kernel = $(call totarget,kernel)

KOBJS	= $(call read_packet,kernel libs)

$(kernel): tools/kernel.ld

$(kernel): $(KOBJS)
	@echo + ld $@
	$(V)$(LD) $(LDFLAGS) -T tools/kernel.ld -o $@ $(KOBJS)

$(call create_target,kernel)

# -------------------------------------------------------------------
# create ucore.img
UCOREIMG	:= $(call totarget,ucore.img)

$(UCOREIMG): $(kernel)
	$(OBJCOPY) $(kernel) --strip-all -O binary $@

$(call create_target,ucore.img)

# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

$(call finish_all)

IGNORE_ALLDEPS	= clean \
				  dist-clean \
				  grade \
				  touch \
				  print-.+ \
				  handin

ifeq ($(call match,$(MAKECMDGOALS),$(IGNORE_ALLDEPS)),0)
-include $(ALLDEPS)
endif

# -------------------------------------------------------------------
# verification

kernelasm = $(call asmfile, kernel)
kernelasmracket = $(call asmracket, kernel)
kernelmap = $(call mapfile, kernel)
kernelmapracket = $(call mapracket, kernel)
kernelglobal = $(call globalfile, kernel)

VERIFY_TEST := \
	verif/refinement.rkt \

$(kernelasm): $(kernel)
	@$(OBJDUMP) -M no-aliases --prefix-address -w -f -d -z --show-raw-insn $< > $@

$(kernelasmracket): $(kernelasm)
	@echo "#lang reader serval/riscv/objdump" > $@~ && \
		cat $< >> $@~
	$(V)mv $@~ $@

# sort addresses for *.map.rkt
$(kernelmap): $(kernel)
	$(V)$(NM) --print-size --numeric-sort "$<" > "$@"

$(kernelmapracket): $(kernelmap)
	@echo "#lang reader serval/lang/nm" > $@~ && \
		cat $< >> $@~
	$(V)mv "$@~" "$@"

$(kernelglobal): $(kernel)
	@echo "#lang reader serval/lang/dwarf" > $@~
	$(V)$(OBJDUMP) --dwarf=info $< >> $@~
	$(V)mv $@~ $@

# ---- LLVM
KCS = $(subst .c,.ll, $(call listf_ll, $(LIBDIR)) $(call listf_ll, $(KSRCDIR)))
KLLS = $(foreach file, $(KCS), $(O)/$(file))

# For simplicity, we can just include all generated llvm irs here
$(O)/kernel.ll: $(KLLS)
	@echo "+ llvm link & opt $<"
	$(QUIET_GEN)$(LLVM_LINK) $^ | $(LLVM_OPT) -o $@~ $(LLVM_OPTFLAGS) -S
	$(Q)mv $@~ $@

# keep LLVM_ROSETTE around for now
$(O)/kernel.ll.rkt: $(O)/kernel.ll $(LLVM_ROSETTE)
	$(QUIET_GEN)$(SERVAL_LLVM) < $< > $@~
	$(Q)mv $@~ $@

.PHONY: verify

$(VERIFY_TEST): $(kernelasmracket) \
	            $(kernelmapracket) \
				$(kernelglobal)    \
				$(O)/kernel.ll.rkt

verify: $(VERIFY_TEST)
	$(RACO_TEST) $^

# files for grade script

TARGETS: $(TARGETS)

.DEFAULT_GOAL := TARGETS

.PHONY: qemu spike
qemu: $(UCOREIMG) $(SWAPIMG) $(SFSIMG)
	$(V)$(QEMU) \
		-machine virt \
		-nographic \
		-bios default \
		-device loader,file=$(UCOREIMG),addr=0x80200000

spike: $(UCOREIMG) $(SWAPIMG) $(SFSIMG)
	$(V)$(SPIKE) $(UCOREIMG)

.PHONY: grade touch

GRADE_GDB_IN	:= .gdb.in
GRADE_QEMU_OUT	:= .qemu.out
HANDIN			:= proj$(PROJ)-handin.tar.gz

TOUCH_FILES		:= kern/trap/trap.c

MAKEOPTS		:= --quiet --no-print-directory

grade:
	$(V)$(MAKE) $(MAKEOPTS) clean
	$(V)$(SH) tools/grade.sh

touch:
	$(V)$(foreach f,$(TOUCH_FILES),$(TOUCH) $(f))

print-%:
	@echo $($(shell echo $(patsubst print-%,%,$@) | $(TR) [a-z] [A-Z]))

.PHONY: clean dist-clean handin packall tags
clean:
	$(V)$(RM) $(GRADE_GDB_IN) $(GRADE_QEMU_OUT) cscope* tags
	-$(RM) -r $(OBJDIR) $(BINDIR)

dist-clean: clean
	-$(RM) $(HANDIN)

handin: packall
	@echo Please visit http://learn.tsinghua.edu.cn and upload $(HANDIN). Thanks!

packall: clean
	@$(RM) -f $(HANDIN)
	@tar -czf $(HANDIN) `find . -type f -o -type d | grep -v '^\.*$$' | grep -vF '$(HANDIN)'`

tags:
	@echo TAGS ALL
	$(V)rm -f cscope.files cscope.in.out cscope.out cscope.po.out tags
	$(V)find . -type f -name "*.[chS]" >cscope.files
	$(V)cscope -bq 
	$(V)ctags -L cscope.files
