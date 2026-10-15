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
  LDLanguages.m \
  LDFileWatcher.m \
  LDFileWatcherLinux.m \
  LDFileWatcherApple.m \
  LDDesktopEntry.m \
  LDMimeApps.m \
  LDOpenWith.m \
  LDOpenWithLinux.m \
  LDUpdates.m

LinDirStat_RESOURCE_FILES = Resources/Info-gnustep.plist $(wildcard Resources/Icons/*.png) $(wildcard Resources/*.lproj)

# libs-OpenSave build (docs/development.md); override with OPENSAVE_ROOT=...
OPENSAVE_ROOT ?= $(HOME)/git/gnustep/libs-OpenSave

ADDITIONAL_OBJCFLAGS += -I$(GNUSTEP_MAKEFILES)/../../../include
ADDITIONAL_OBJCFLAGS += -I$(OPENSAVE_ROOT)/Headers
ADDITIONAL_CPPFLAGS += -I$(GNUSTEP_MAKEFILES)/../../../include
ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_MAKEFILES)/../../../lib -L$(GNUSTEP_MAKEFILES)/../../../lib64
ADDITIONAL_LIB_DIRS += -L$(OPENSAVE_ROOT)/Source/obj
ADDITIONAL_GUI_LIBS += -lOpenSave
ADDITIONAL_OBJC_LIBS += -ldispatch -lnettle
ADDITIONAL_LDFLAGS += -Wl,-rpath,$(OPENSAVE_ROOT)/Source/obj

# The in-app updater (vendor/gnustep-packager-updater, built first): its
# two static libraries, and gp-update-helper copied next to the executable,
# where the updater looks for it.
UPDATER_ROOT = ../vendor/gnustep-packager-updater
ADDITIONAL_OBJCFLAGS += -I$(UPDATER_ROOT)/GPUpdaterCore/Headers -I$(UPDATER_ROOT)/GPUpdaterUI/Headers
ADDITIONAL_LIB_DIRS += -L$(UPDATER_ROOT)/GPUpdaterUI/$(GNUSTEP_OBJ_DIR) -L$(UPDATER_ROOT)/GPUpdaterCore/$(GNUSTEP_OBJ_DIR)
ADDITIONAL_GUI_LIBS += -lGPUpdaterUI -lGPUpdaterCore

# The info panel's release: package.version from the packaging manifest (read
# as macos/GNUmakefile does), the one place the version is kept, unless the
# build runs with GP_PACKAGE_VERSION_OVERRIDE set, gnustep-packager's input
# for a version other than the manifest's.
APP_RELEASE := $(or $(GP_PACKAGE_VERSION_OVERRIDE),$(shell sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' ../package.manifest.json | head -1))

include $(GNUSTEP_MAKEFILES)/application.make

before-all::
	$(MAKE) -C $(UPDATER_ROOT)

after-all::
	cp $(UPDATER_ROOT)/gp-update-helper/$(GNUSTEP_OBJ_DIR)/gp-update-helper $(APP_NAME).app/gp-update-helper
	echo '{ ApplicationRelease = "$(APP_RELEASE)"; }' > $(GNUSTEP_OBJ_DIR)/ApplicationRelease.plist
	plmerge $(APP_NAME).app/Resources/Info-gnustep.plist $(GNUSTEP_OBJ_DIR)/ApplicationRelease.plist

after-clean::
	$(MAKE) -C $(UPDATER_ROOT) clean
