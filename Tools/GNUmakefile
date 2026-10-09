include $(GNUSTEP_MAKEFILES)/common.make

ADDITIONAL_OBJCFLAGS += -fobjc-arc -I$(GNUSTEP_MAKEFILES)/../../../include
ADDITIONAL_TOOL_LIBS += -ldispatch

TOOL_NAME = windirstat-parity-exporter

windirstat-parity-exporter_OBJC_FILES = \
  TreemapParityExporter.m \
  ../Source/LDFileNode.m \
  ../Source/LDExtensionStats.m \
  ../Source/LDScanSession.m \
  ../Source/LDScanner.m \
  ../Source/LDScanOptions.m \
  ../Source/LDTreemapItem.m \
  ../Source/LDTreemapLayout.m \
  ../Source/LDExtensionColor.m \
  ../Source/LDScanClock.m

windirstat-parity-exporter_INCLUDE_DIRS = -I../Source

include $(GNUSTEP_MAKEFILES)/tool.make
