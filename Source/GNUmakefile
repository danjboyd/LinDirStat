include $(GNUSTEP_MAKEFILES)/common.make

ADDITIONAL_OBJCFLAGS += -fobjc-arc

APP_NAME = LinDirStat

LinDirStat_OBJC_FILES = \
  main.m \
  AppController.m \
  LDFileNode.m \
  LDExtensionStats.m \
  LDSizeFormatter.m \
  LDScanSession.m \
  LDScanResults.m \
  LDProfiling.m \
  LDScanner.m \
  LDTreemapItem.m \
  LDTreemapLayout.m \
  LDExtensionColor.m \
  LDTreemapView.m \
  LDFileTypeDescriptions.m \
  LDTreeSorting.m \
  LDSystemInfo.m \
  LDTreeCells.m \
  LDFileOperations.m \
  LDDesktop.m \
  LDPreferences.m \
  LDCommandRules.m \
  LDCustomCleanupRunner.m \
  LDDialogs.m \
  LDListViews.m \
  AppController+Cleanup.m \
  AppController+FileLists.m \
  AppController+HardLinks.m \
  AppController+LayoutDump.m \
  LDLayoutDump.m \
  LDFileAttributes.m \
  LDCSV.m \
  LDCommandLine.m \
  LDNodeRanking.m \
  LDHardLinks.m \
  LDHasher.m \
  LDLargestFiles.m \
  LDDuplicateFinder.m \
  LDSearch.m \
  LDFilterPatterns.m \
  LDOptionsWindowController.m \
  LDScanOptions.m \
  LDVolumes.m \
  LDSpaceItems.m \
  LDSelectTargetRules.m \
  LDSelectTargetPanel.m \
  LDPlatformUI.m \
  LDScanClock.m \
  LDScanProgress.m \
  LDTabCycle.m \
  LDTreemapPreview.m \
  LDMainWindow.m \
  LDPrivacyAccess.m \
  LDFileWatcher.m \
  LDFileWatcherLinux.m \
  LDFileWatcherApple.m \
  LDDesktopEntry.m \
  LDMimeApps.m \
  LDOpenWith.m \
  LDOpenWithLinux.m

LinDirStat_RESOURCE_FILES = Resources/Info-gnustep.plist $(wildcard Resources/Icons/*.png)

OPENSAVE_ROOT = /home/danboyd/git/gnustep/libs-OpenSave

ADDITIONAL_OBJCFLAGS += -I$(GNUSTEP_MAKEFILES)/../../../include
ADDITIONAL_OBJCFLAGS += -I$(OPENSAVE_ROOT)/Headers
ADDITIONAL_CPPFLAGS += -I$(GNUSTEP_MAKEFILES)/../../../include
ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_MAKEFILES)/../../../lib -L$(GNUSTEP_MAKEFILES)/../../../lib64
ADDITIONAL_LIB_DIRS += -L$(OPENSAVE_ROOT)/Source/obj
ADDITIONAL_GUI_LIBS += -lOpenSave
ADDITIONAL_OBJC_LIBS += -ldispatch -lnettle
ADDITIONAL_LDFLAGS += -Wl,-rpath,$(OPENSAVE_ROOT)/Source/obj

include $(GNUSTEP_MAKEFILES)/application.make
