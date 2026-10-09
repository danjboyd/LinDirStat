#import <Foundation/Foundation.h>
#import "LDFileNode.h"
#import "LDScanSession.h"
#import "LDScanOptions.h"
#import "LDExtensionStats.h"
#import "LDTreemapLayout.h"
#import "LDLargestFiles.h"
#import "LDDuplicateFinder.h"
#import "LDScanResults.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <unistd.h>

// Headless benchmark of a scan and of what the app does when one completes
// (see docs/performance.md). Prints one "key value" line per measurement.

static double Now(void)
{
  return [NSDate timeIntervalSinceReferenceDate];
}

static double PeakRSSMegabytes(void)
{
  struct rusage usage;
  getrusage(RUSAGE_SELF, &usage);
  return (double)usage.ru_maxrss / 1024.0;
}

static double CurrentRSSMegabytes(void)
{
  long pages = 0;
  long resident = 0;
  FILE *file = fopen("/proc/self/statm", "r");
  if (!file) {
    return 0.0;
  }
  if (fscanf(file, "%ld %ld", &pages, &resident) != 2) {
    resident = 0;
  }
  fclose(file);
  return (double)resident * (double)sysconf(_SC_PAGESIZE) / (1024.0 * 1024.0);
}

static void Report(const char *key, double value)
{
  printf("%-34s %10.3f\n", key, value);
  fflush(stdout);
}

static void RunLoopUntil(BOOL (^done)(void), double deadline)
{
  while (!done() && (deadline <= 0 || Now() < deadline)) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
  }
}

static void PrintUsage(void)
{
  fprintf(stderr, "usage: lindirstat-bench path [--threads N] [--dupes] [--logical] [--stop-after seconds]\n"
                  "                         [--wait-dupes] [--no-results] [--width W] [--height H] [--largest N]\n");
}

int main(int argc, const char *argv[])
{
  @autoreleasepool {
    if (argc < 2) {
      PrintUsage();
      return 2;
    }
    NSString *path = [NSString stringWithUTF8String:argv[1]];
    NSUInteger threads = 4;
    BOOL dupes = NO;
    BOOL waitDupes = NO;
    LDSizeMetric metric = LDSizeMetricPhysical;
    double stopAfter = 0.0;
    int width = 1200;
    int height = 500;
    NSUInteger largest = 50;
    BOOL backgroundResults = YES;
    for (int index = 2; index < argc; index++) {
      const char *arg = argv[index];
      BOOL hasValue = index + 1 < argc;
      if (strcmp(arg, "--threads") == 0 && hasValue) {
        threads = (NSUInteger)atoi(argv[++index]);
      } else if (strcmp(arg, "--dupes") == 0) {
        dupes = YES;
      } else if (strcmp(arg, "--wait-dupes") == 0) {
        dupes = YES;
        waitDupes = YES;
      } else if (strcmp(arg, "--no-results") == 0) {
        backgroundResults = NO;
      } else if (strcmp(arg, "--logical") == 0) {
        metric = LDSizeMetricLogical;
      } else if (strcmp(arg, "--stop-after") == 0 && hasValue) {
        stopAfter = atof(argv[++index]);
      } else if (strcmp(arg, "--width") == 0 && hasValue) {
        width = atoi(argv[++index]);
      } else if (strcmp(arg, "--height") == 0 && hasValue) {
        height = atoi(argv[++index]);
      } else if (strcmp(arg, "--largest") == 0 && hasValue) {
        largest = (NSUInteger)atoi(argv[++index]);
      } else {
        PrintUsage();
        return 2;
      }
    }

    LDScanOptions *options = [[LDScanOptions alloc] init];
    [options setThreadCount:threads];
    [options setFindsDuplicates:dupes];
    LDScanSession *session = [[LDScanSession alloc] init];
    [session setScanOptions:options];
    [session setSortMetric:metric];
    if (backgroundResults) {
      LDScanResultsRequest *request = [LDScanResultsRequest requestWithMetric:metric largestFileCount:largest];
      [request setTreemapWidth:width height:height options:LDTreemapDefaultOptions()];
      [session setResultsRequest:request];
    }

    __block double completedAt = 0.0;
    double started = Now();
    [session startAsyncScanPath:path completion:^{
      completedAt = Now();
    }];
    double stoppedAt = 0.0;
    if (stopAfter > 0.0) {
      RunLoopUntil(^BOOL { return completedAt > 0.0; }, started + stopAfter);
      if (completedAt == 0.0) {
        stoppedAt = Now();
        [session cancel];
      }
    }
    RunLoopUntil(^BOOL { return completedAt > 0.0; }, 0);

    LDFileNode *root = [session rootNode];
    printf("path %s threads %lu duplicates %s metric %s results %s stopped %s\n", argv[1], (unsigned long)threads,
           dupes ? "on" : "off", metric == LDSizeMetricLogical ? "logical" : "physical",
           backgroundResults ? "background" : "main",
           stoppedAt > 0.0 ? "yes" : "no");
    Report("files", (double)[root fileCount]);
    Report("folders", (double)[root directoryCount]);
    Report("scan_s (read)", [session readDuration]);
    Report("finalize_s (recalc+sort)", [session finishDuration]);
    Report("results_s (background)", [session resultsDuration]);
    Report("scan_total_s", completedAt - started);
    if (stoppedAt > 0.0) {
      Report("stop_to_completion_s", completedAt - stoppedAt);
    }
    Report("rss_after_scan_mb", CurrentRSSMegabytes());

    // What -finishAsyncScan does on the main thread, as the model sees it.
    LDScanResults *results = [session results];
    double t = Now();
    NSArray *stats = results ? [results extensionStats] : [LDExtensionStats sortedStatsForRootNode:root metric:metric];
    NSDictionary *colors = [LDExtensionStats colorIndexMapForSortedStats:stats];
    Report("main_extension_stats_s", Now() - t);

    LDTreemap *treemap = [results treemap];
    if (!treemap) {
      t = Now();
      treemap = [[LDTreemap alloc] initWithRootNode:root metric:metric width:width height:height
                                            options:LDTreemapDefaultOptions()];
      Report("main_treemap_layout_s", Now() - t);
      t = Now();
      NSData *pixels = [treemap renderRGBAWithColorIndexes:colors];
      Report("main_treemap_render_s", Now() - t);
      (void)pixels;
    }
    Report("treemap_cells", (double)[treemap cellCount]);

    t = Now();
    NSArray *files = results ? [results largestFiles] : [LDLargestFiles largestFilesUnderNode:root count:largest];
    Report("main_largest_files_s", Now() - t);
    (void)files;

    LDDuplicateCollector *collector = [session duplicateCollector];
    if (collector) {
      t = Now();
      NSArray *groups = [collector groups];
      Report("main_duplicate_groups_s", Now() - t);
      Report("duplicate_groups_so_far", (double)[groups count]);
      if (waitDupes) {
        t = Now();
        [collector waitUntilFinished];
        Report("duplicates_finish_wait_s", Now() - t);
        Report("duplicate_groups", (double)[[collector groups] count]);
      }
    } else if (dupes) {
      // A canceled scan without a collector: what a loaded tree costs.
      t = Now();
      LDDuplicateFinder *finder = [[LDDuplicateFinder alloc] initWithRootNode:root];
      [finder startWithProgress:nil completion:nil];
      [finder cancel];
      Report("main_duplicate_snapshot_s", Now() - t);
    }
    Report("rss_end_mb", CurrentRSSMegabytes());
    Report("peak_rss_mb", PeakRSSMegabytes());

    t = Now();
    treemap = nil;
    results = nil;
    collector = nil;
    root = nil;
    session = nil;
    Report("free_tree_s", Now() - t);
  }
  return 0;
}
