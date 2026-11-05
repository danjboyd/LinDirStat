# Included after common.make by every GNUmakefile that compiles LinDirStat's
# code. The gnustep-cli toolchain's gnustep-make has no -O in OPTFLAG, so with
# debug=no it would compile at -O0 (#179). -O2 -DNDEBUG is what the Mac release
# build uses. debug=yes stays unoptimized, as gnustep-make intends.
ifneq ($(debug),yes)
ADDITIONAL_OBJCFLAGS += -O2 -DNDEBUG
ADDITIONAL_CFLAGS += -O2 -DNDEBUG
endif
