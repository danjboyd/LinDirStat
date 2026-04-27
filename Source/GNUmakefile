include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = LinDirStat

LinDirStat_OBJC_FILES = \
  main.m \
  AppController.m \
  LDFileNode.m \
  LDExtensionStats.m \
  LDSizeFormatter.m \
  LDScanSession.m \
  LDScanner.m \
  LDTreemapItem.m \
  LDTreemapLayout.m \
  LDExtensionColor.m \
  LDTreemapView.m \
  LDFileActionPlan.m \
  LDFileActions.m

LinDirStat_RESOURCE_FILES = Resources/Info-gnustep.plist

OPENSAVE_ROOT = /home/danboyd/git/gnustep/libs-OpenSave

ADDITIONAL_OBJCFLAGS += -I$(GNUSTEP_MAKEFILES)/../../../include
ADDITIONAL_OBJCFLAGS += -I$(OPENSAVE_ROOT)/Headers
ADDITIONAL_CPPFLAGS += -I$(GNUSTEP_MAKEFILES)/../../../include
ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_MAKEFILES)/../../../lib -L$(GNUSTEP_MAKEFILES)/../../../lib64
ADDITIONAL_LIB_DIRS += -L$(OPENSAVE_ROOT)/Source/obj
ADDITIONAL_GUI_LIBS += -lOpenSave
ADDITIONAL_OBJC_LIBS += -ldispatch
ADDITIONAL_LDFLAGS += -Wl,-rpath,$(OPENSAVE_ROOT)/Source/obj

include $(GNUSTEP_MAKEFILES)/application.make
