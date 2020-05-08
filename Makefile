PROJ	:= lab2
EMPTY	:=
SPACE	:= $(EMPTY) $(EMPTY)
SLASH	:= /

V       := @

-include local.mk

ifndef GCCPREFIX
ifeq ($(shell cat /proc/version | grep 'Ubuntu'), )
GCCPREFIX := riscv64-suse-linux-gnu-
else
GCCPREFIX := riscv64-linux-gnu-
endif
endif

ifndef QEMU
QEMU := qemu-system-riscv64
endif

ifndef SPIKE
SPIKE := spike
endif

# eliminate default suffix rules
.SUFFIXES: .c .S .h

# delete target files if there is an error (or make is interrupted)
.DELETE_ON_ERROR:

# define compiler and flags
HOSTCC		:= gcc
HOSTCFLAGS	:= -Wall -O2

GDB		:= $(GCCPREFIX)gdb

CC		:= $(GCCPREFIX)gcc

ifdef ENABLE_PRINT
CONFIG_FLAGS += -DENABLE_PRINT=$(ENABLE_PRINT)
endif

CFLAGS     := -ffreestanding
CFLAGS     += -fno-stack-protector
CFLAGS     += -fno-strict-aliasing
CFLAGS     += -fno-jump-tables
CFLAGS     += -mstrict-align
CFLAGS     += -O2 -nostdinc $(DEFS)
CFLAGS     += -Wno-unused -Wall -Werror 
#CFLAGS   += -MP -MD 
CFLAGS     += -mcmodel=medany
CFLAGS     += -mabi=lp64
CFLAGS     += -ffunction-sections -fdata-sections
CFLAGS     += -fno-PIE
CFLAGS     += -march=rv64ima
CFLAGS     += -std=gnu99
CFLAGS     += -g
CFLAGS	   += $(CONFIG_FLAGS)

CTYPE	:= c S

LD      := $(GCCPREFIX)ld
LDFLAGS	:= -m elf64lriscv
LDFLAGS	+= -nostdlib --gc-sections

OBJCOPY := $(GCCPREFIX)objcopy
OBJDUMP := $(GCCPREFIX)objdump

NM := $(GCCPREFIX)nm

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

include tools/function.mk

listf_cc = $(call listf,$(1),$(CTYPE))

# for cc
add_files_cc = $(call add_files,$(1),$(CC),$(CFLAGS) $(3),$(2),$(4))
create_target_cc = $(call create_target,$(1),$(2),$(3),$(CC),$(CFLAGS))

# for hostcc
add_files_host = $(call add_files,$(1),$(HOSTCC),$(HOSTCFLAGS),$(2),$(3))
create_target_host = $(call create_target,$(1),$(2),$(3),$(HOSTCC),$(HOSTCFLAGS))

cgtype = $(patsubst %.$(2),%.$(3),$(1))
objfile = $(call toobj,$(1))
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

$(call add_files_cc,$(call listf_cc,$(KSRCDIR)),kernel,$(KCFLAGS))

KOBJS	= $(call read_packet,kernel libs)

# create kernel target
kernel = $(call totarget,kernel)

$(kernel): tools/kernel.ld

$(kernel): $(KOBJS)
	@echo + ld $@
	$(V)$(LD) $(LDFLAGS) -T tools/kernel.ld -o $@ $(KOBJS)

$(call create_target,kernel)

# -------------------------------------------------------------------
# create ucore.img
UCOREIMG	:= $(call totarget,ucore.img)

# $(UCOREIMG): $(kernel)
#	cd ../../riscv-pk && rm -rf build && mkdir build && cd build && ../configure --prefix=$(RISCV) --host=riscv64-unknown-elf --with-payload=../../labcodes/$(PROJ)/$(kernel)  --disable-fp-emulation && make && cp bbl ../../labcodes/$(PROJ)/$(UCOREIMG)

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
	verif/test.rkt \

RACO_JOBS               = 1
RACO_TIMEOUT            = 1200
RACO_TEST               = raco test --check-stderr --table --timeout $(RACO_TIMEOUT) --jobs $(RACO_JOBS)

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

.PHONY: verify

$(VERIFY_TEST): $(kernelasmracket) $(kernelmapracket) $(kernelglobal)

verify: $(VERIFY_TEST)
	$(RACO_TEST) $^

# files for grade script

TARGETS: $(TARGETS)

.DEFAULT_GOAL := TARGETS

.PHONY: qemu spike
qemu: $(UCOREIMG) $(SWAPIMG) $(SFSIMG)
#	$(V)$(QEMU) -kernel $(UCOREIMG) -nographic
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
