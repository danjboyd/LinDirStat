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
  LDScanSessionTests.m \
  LDFileOperationsTests.m \
  LDPreferencesTests.m \
  LDCommandRulesTests.m \
  LDCustomCleanupRunnerTests.m \
  LDCSVTests.m \
  LDHasherTests.m \
  LDLargestFilesTests.m \
  LDDuplicateFinderTests.m \
  LDSearchTests.m \
  LDFilterPatternsTests.m \
  LDScanOptionsTests.m \
  LDVolumesTests.m \
  LDSelectTargetRulesTests.m \
  LDPrivacyAccessTests.m \
  ../Source/LDFileNode.m \
  ../Source/LDExtensionStats.m \
  ../Source/LDSizeFormatter.m \
  ../Source/LDScanSession.m \
  ../Source/LDScanner.m \
  ../Source/LDTreemapItem.m \
  ../Source/LDTreemapLayout.m \
  ../Source/LDExtensionColor.m \
  ../Source/LDFileTypeDescriptions.m \
  ../Source/LDTreeSorting.m \
  ../Source/LDFileOperations.m \
  ../Source/LDDesktop.m \
  ../Source/LDPreferences.m \
  ../Source/LDCommandRules.m \
  ../Source/LDCustomCleanupRunner.m \
  ../Source/LDFileAttributes.m \
  ../Source/LDCSV.m \
  ../Source/LDNodeRanking.m \
  ../Source/LDHasher.m \
  ../Source/LDLargestFiles.m \
  ../Source/LDDuplicateFinder.m \
  ../Source/LDSearch.m \
  ../Source/LDFilterPatterns.m \
  ../Source/LDScanOptions.m \
  ../Source/LDVolumes.m \
  ../Source/LDSelectTargetRules.m \
  ../Source/LDPrivacyAccess.m

LinDirStatTests_INCLUDE_DIRS = -I../Source -I.
ifneq ($(TOOLS_XCTEST_ROOT),)
LinDirStatTests_INCLUDE_DIRS += -I$(TOOLS_XCTEST_ROOT)
LinDirStatTests_LIB_DIRS += -L$(TOOLS_XCTEST_ROOT)/XCTest/obj
endif
LinDirStatTests_BUNDLE_LIBS += -lXCTest -ldispatch -lnettle
LinDirStatTests_RESOURCE_FILES =

include $(GNUSTEP_MAKEFILES)/bundle.make
