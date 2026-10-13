include $(GNUSTEP_MAKEFILES)/common.make

ADDITIONAL_OBJCFLAGS += -fobjc-arc -I$(GNUSTEP_MAKEFILES)/../../../include
ADDITIONAL_TOOL_LIBS += -ldispatch -lnettle

TOOL_NAME = windirstat-parity-exporter lindirstat-bench

windirstat-parity-exporter_OBJC_FILES = \
  TreemapParityExporter.m \
  ../Source/LDFileNode.m \
  ../Source/LDExtensionStats.m \
  ../Source/LDScanSession.m \
  ../Source/LDScanResults.m \
  ../Source/LDLargestFiles.m \
  ../Source/LDScanner.m \
  ../Source/LDScanOptions.m \
  ../Source/LDDuplicateFinder.m \
  ../Source/LDHasher.m \
  ../Source/LDNodeRanking.m \
  ../Source/LDHardLinks.m \
  ../Source/LDTreemapItem.m \
  ../Source/LDTreemapLayout.m \
  ../Source/LDExtensionColor.m \
  ../Source/LDScanClock.m

windirstat-parity-exporter_INCLUDE_DIRS = -I../Source

# Headless scan and completion benchmark (scripts/bench-scan.sh).
lindirstat-bench_OBJC_FILES = ScanBenchmark.m $(filter-out TreemapParityExporter.m,$(windirstat-parity-exporter_OBJC_FILES))
lindirstat-bench_INCLUDE_DIRS = -I../Source

include $(GNUSTEP_MAKEFILES)/tool.make

# Both tools compile the same ../Source files into the same objects
# (obj/<tool>.obj/../Source is obj/Source for each), so building them at
# once under make -j makes them race on those files. Build the benchmark
# after the exporter: its own files still compile in parallel, and it finds
# the shared objects already built.
lindirstat-bench.all.tool.variables: windirstat-parity-exporter.all.tool.variables
