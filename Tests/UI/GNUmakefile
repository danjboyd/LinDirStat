# UI coordination tests: the real AppController and its window, driven
# without user input. They need a display; run them with
# scripts/run-ui-tests.sh, which starts a private Xvfb and uses a private
# HOME, XDG_DATA_HOME and TMPDIR. On macOS, make -C macos ui-test builds and
# runs them (scripts/run-ui-tests-macos.sh).

# Objects and the bundle go to build/, so the app's sources (../../Source)
# are compiled under build/Source rather than next to this file.
GNUSTEP_BUILD_DIR = $(CURDIR)/build

include $(GNUSTEP_MAKEFILES)/common.make

ADDITIONAL_OBJCFLAGS += -fobjc-arc -I$(GNUSTEP_MAKEFILES)/../../../include

BUNDLE_NAME = LinDirStatUITests
NEEDS_GUI = yes

# Every source of the app except main.m, from the app's own list.
APP_SOURCES := $(filter-out main.m,$(shell sed -n '/_OBJC_FILES *=/,/^ *$$/p' ../../Source/GNUmakefile | grep -o '[A-Za-z0-9_+]*\.m'))

LinDirStatUITests_OBJC_FILES = \
  LDAppControllerUITests.m \
  $(addprefix ../../Source/,$(APP_SOURCES))

# libs-OpenSave build (docs/development.md); override with OPENSAVE_ROOT=...
OPENSAVE_ROOT ?= $(HOME)/git/gnustep/libs-OpenSave

LinDirStatUITests_INCLUDE_DIRS = -I../../Source -I. -I$(OPENSAVE_ROOT)/Headers
ifneq ($(TOOLS_XCTEST_ROOT),)
LinDirStatUITests_INCLUDE_DIRS += -I$(TOOLS_XCTEST_ROOT)
LinDirStatUITests_LIB_DIRS += -L$(TOOLS_XCTEST_ROOT)/XCTest/obj
endif
LinDirStatUITests_LIB_DIRS += -L$(GNUSTEP_MAKEFILES)/../../../lib -L$(GNUSTEP_MAKEFILES)/../../../lib64 -L$(OPENSAVE_ROOT)/Source/obj
LinDirStatUITests_BUNDLE_LIBS += -lXCTest -lOpenSave -ldispatch -lnettle
ADDITIONAL_LDFLAGS += -Wl,-rpath,$(OPENSAVE_ROOT)/Source/obj

# The updater (built by make -C Source).
UPDATER_ROOT = ../../vendor/gnustep-packager-updater
LinDirStatUITests_INCLUDE_DIRS += -I$(UPDATER_ROOT)/GPUpdaterCore/Headers -I$(UPDATER_ROOT)/GPUpdaterUI/Headers
LinDirStatUITests_LIB_DIRS += -L$(UPDATER_ROOT)/GPUpdaterUI/obj -L$(UPDATER_ROOT)/GPUpdaterCore/obj
LinDirStatUITests_BUNDLE_LIBS += -lGPUpdaterUI -lGPUpdaterCore
LinDirStatUITests_RESOURCE_FILES =

include $(GNUSTEP_MAKEFILES)/bundle.make
