include $(GNUSTEP_MAKEFILES)/common.make

ADDITIONAL_OBJCFLAGS += -fobjc-arc -I$(GNUSTEP_MAKEFILES)/../../../include

BUNDLE_NAME = LinDirStatTests
NEEDS_GUI = yes

LinDirStatTests_OBJC_FILES = \
  LDFileNodeTests.m \
  LDExtensionStatsTests.m \
  LDSizeFormatterTests.m \
  LDScannerTests.m \
  LDTreemapLayoutTests.m \
  LDExtensionColorTests.m \
  LDFileTypeDescriptionsTests.m \
  LDTreeSortingTests.m \
  LDFileActionTests.m \
  LDScanSessionTests.m \
  LDFileOperationsTests.m \
  LDPreferencesTests.m \
  LDCSVTests.m \
  ../Source/LDFileNode.m \
  ../Source/LDExtensionStats.m \
  ../Source/LDSizeFormatter.m \
  ../Source/LDScanSession.m \
  ../Source/LDScanner.m \
  ../Source/LDTreemapItem.m \
  ../Source/LDTreemapLayout.m \
  ../Source/LDExtensionColor.m \
  ../Source/LDFileActionPlan.m \
  ../Source/LDFileActions.m \
  ../Source/LDFileTypeDescriptions.m \
  ../Source/LDTreeSorting.m \
  ../Source/LDFileOperations.m \
  ../Source/LDDesktop.m \
  ../Source/LDPreferences.m \
  ../Source/LDFileAttributes.m \
  ../Source/LDCSV.m

LinDirStatTests_INCLUDE_DIRS = -I../Source -I.
ifneq ($(TOOLS_XCTEST_ROOT),)
LinDirStatTests_INCLUDE_DIRS += -I$(TOOLS_XCTEST_ROOT)
LinDirStatTests_LIB_DIRS += -L$(TOOLS_XCTEST_ROOT)/XCTest/obj
endif
LinDirStatTests_BUNDLE_LIBS += -lXCTest -ldispatch
LinDirStatTests_RESOURCE_FILES =

include $(GNUSTEP_MAKEFILES)/bundle.make
