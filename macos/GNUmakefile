# Native macOS build of LinDirStat against Apple's AppKit (no GNUstep).
#
#   make -C macos            # build/LinDirStat.app (universal, ad-hoc signed)
#   make -C macos run        # build and launch
#   make -C macos test       # the Tests/ suite with Apple's XCTest
#   make -C macos zip        # build/LinDirStat-<version>-macos.zip
#
# Needs only Xcode or the Command Line Tools. Without an Apple Developer ID
# the bundle is ad-hoc signed, not notarized (see docs/macos.md).

ROOT      := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
SRC       := $(ROOT)/Source
BUILD     := $(ROOT)/macos/build
APP       := $(BUILD)/LinDirStat.app
OBJDIR    := $(BUILD)/obj

VERSION   ?= $(shell git -C $(ROOT) describe --tags --always 2>/dev/null | sed 's/^v//' || echo 0.0)
BUILDNUM  ?= $(shell git -C $(ROOT) rev-list --count HEAD 2>/dev/null || echo 1)
MIN_MACOS ?= 13.0
ARCHS     ?= arm64 x86_64
CONFIG    ?= release
SIGN_ID   ?= -

# One source list, shared with the GNUstep build.
SOURCES := $(shell sed -n '/_OBJC_FILES *=/,/^ *$$/p' $(SRC)/GNUmakefile | grep -o '[A-Za-z0-9_+]*\.m')
ICONS   := $(wildcard $(SRC)/Resources/Icons/*.png)

CC      := xcrun clang
ARCHFLAGS := $(foreach a,$(ARCHS),-arch $(a))
CFLAGS  := -fobjc-arc -fmodules -mmacosx-version-min=$(MIN_MACOS) $(ARCHFLAGS) \
           -Wall -Wno-deprecated-declarations -Wno-unused-function -I$(SRC)
ifeq ($(CONFIG),debug)
CFLAGS  += -g -O0
else
CFLAGS  += -O2 -DNDEBUG -g
endif
LDFLAGS := -mmacosx-version-min=$(MIN_MACOS) $(ARCHFLAGS) \
           -framework AppKit -framework UniformTypeIdentifiers

OBJECTS := $(patsubst %.m,$(OBJDIR)/%.o,$(SOURCES))

.PHONY: all app run zip clean test
all: app

app: $(APP)/Contents/MacOS/LinDirStat $(APP)/Contents/Info.plist resources
	codesign --force --deep --options runtime --timestamp=none \
	  --entitlements $(ROOT)/macos/LinDirStat.entitlements -s "$(SIGN_ID)" $(APP)

$(OBJDIR)/%.o: $(SRC)/%.m $(wildcard $(SRC)/*.h) | $(OBJDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJDIR):
	mkdir -p $@

$(APP)/Contents/MacOS/LinDirStat: $(OBJECTS)
	mkdir -p $(dir $@)
	$(CC) $(LDFLAGS) $^ -o $@

$(APP)/Contents/Info.plist: $(ROOT)/macos/Info.plist
	mkdir -p $(dir $@)
	sed -e 's/@VERSION@/$(VERSION)/' -e 's/@BUILD@/$(BUILDNUM)/' -e 's/@MIN_MACOS@/$(MIN_MACOS)/' $< > $@
	printf 'APPL????' > $(APP)/Contents/PkgInfo

.PHONY: resources
resources:
	mkdir -p $(APP)/Contents/Resources
	cp $(ICONS) $(APP)/Contents/Resources/
	if [ -f $(ROOT)/macos/LinDirStat.icns ]; then cp $(ROOT)/macos/LinDirStat.icns $(APP)/Contents/Resources/; fi

run: app
	open $(APP)

zip: app
	cd $(BUILD) && ditto -c -k --keepParent LinDirStat.app LinDirStat-$(VERSION)-macos.zip

# The Tests/ suite (same file list as Tests/GNUmakefile) as an XCTest bundle.
TESTS    := $(ROOT)/Tests
TEST_SRC := $(shell sed -n '/_OBJC_FILES *=/,/^ *$$/p' $(TESTS)/GNUmakefile | grep -o '[A-Za-z0-9_+./]*\.m')
XCT      := $(BUILD)/LinDirStatTests.xctest
PLATFORM_DEV := $(shell xcrun --show-sdk-platform-path)/Developer
TEST_FLAGS := -fobjc-arc -fmodules -mmacosx-version-min=$(MIN_MACOS) -g -O0 \
              -Wno-deprecated-declarations -Wno-unused-function \
              -I$(SRC) -I$(TESTS) -F$(PLATFORM_DEV)/Library/Frameworks

test:
	mkdir -p $(XCT)/Contents/MacOS
	cd $(TESTS) && $(CC) $(TEST_FLAGS) -bundle $(TEST_SRC) -o $(XCT)/Contents/MacOS/LinDirStatTests \
	  -framework XCTest -framework AppKit -framework UniformTypeIdentifiers \
	  -Wl,-rpath,$(PLATFORM_DEV)/Library/Frameworks -Wl,-rpath,$(PLATFORM_DEV)/usr/lib
	printf '%s' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>LinDirStatTests</string><key>CFBundleIdentifier</key><string>io.github.danjboyd.LinDirStatTests</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>' > $(XCT)/Contents/Info.plist
	cd $(ROOT) && xcrun xctest $(XCT)

clean:
	rm -rf $(BUILD)
