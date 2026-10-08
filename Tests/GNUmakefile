include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = LinDirStatTests
NEEDS_GUI = yes

LinDirStatTests_OBJC_FILES = \
  LDFileNodeTests.m \
  LDExtensionStatsTests.m \
  LDSizeFormatterTests.m \
  LDScannerTests.m \
  LDTreemapLayoutTests.m \
  LDExtensionColorTests.m \
  LDFileActionTests.m \
  LDScanSessionTests.m \
  ../Source/LDFileNode.m \
  ../Source/LDExtensionStats.m \
  ../Source/LDSizeFormatter.m \
  ../Source/LDScanSession.m \
  ../Source/LDScanner.m \
  ../Source/LDTreemapItem.m \
  ../Source/LDTreemapLayout.m \
  ../Source/LDExtensionColor.m \
  ../Source/LDFileActionPlan.m \
  ../Source/LDFileActions.m

LinDirStatTests_INCLUDE_DIRS = -I../Source -I.
ifneq ($(TOOLS_XCTEST_ROOT),)
LinDirStatTests_INCLUDE_DIRS += -I$(TOOLS_XCTEST_ROOT)
LinDirStatTests_LIB_DIRS += -L$(TOOLS_XCTEST_ROOT)/XCTest/obj
endif
LinDirStatTests_BUNDLE_LIBS += -lXCTest
LinDirStatTests_RESOURCE_FILES =

include $(GNUSTEP_MAKEFILES)/bundle.make
