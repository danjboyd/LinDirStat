include $(GNUSTEP_MAKEFILES)/common.make

ADDITIONAL_OBJCFLAGS += -fobjc-arc

TOOL_NAME = windirstat-parity-exporter

windirstat-parity-exporter_OBJC_FILES = \
  TreemapParityExporter.m \
  ../Source/LDFileNode.m \
  ../Source/LDExtensionStats.m \
  ../Source/LDScanSession.m \
  ../Source/LDScanner.m \
  ../Source/LDTreemapItem.m \
  ../Source/LDTreemapLayout.m \
  ../Source/LDExtensionColor.m

windirstat-parity-exporter_INCLUDE_DIRS = -I../Source

include $(GNUSTEP_MAKEFILES)/tool.make
