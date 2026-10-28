#import <Foundation/Foundation.h>
#import "LDFileNode.h"
#import "LDScanner.h"
#import "LDScanSession.h"
#import "LDTreemapItem.h"
#import "LDExtensionStats.h"
#import "LDTreemapLayout.h"

// The options to render with: the defaults, a WinDirStat 2.9 colour preset
// (--preset classic|calm|flat|pastel|high-contrast) and the layout style
// (--style kdirstat|sequoia). An Auto grid colour uses white and black as
// the window and text colours.
static LDTreemapOptions ExportOptions;

static void PrintUsage(void)
{
  fprintf(stderr, "usage: windirstat-parity-exporter [--preset name] [--style name] fixtures.json fixture-name width height [--ppm out.ppm]\n");
  fprintf(stderr, "       windirstat-parity-exporter [--preset name] [--style name] --path path width [--ppm out.ppm]\n");
}

static BOOL ParseOption(const char *flag, const char *value)
{
  if (strcmp(flag, "--preset") == 0) {
    const char *names[] = {"classic", "calm", "flat", "pastel", "high-contrast"};
    int preset = 0;
    for (preset = 0; preset < LDTreemapPresetCount; preset++) {
      if (strcmp(value, names[preset]) == 0) {
        LDTreemapStyle style = ExportOptions.style;
        ExportOptions = LDTreemapPresetOptions((LDTreemapPreset)preset);
        ExportOptions.style = style;
        return YES;
      }
    }
    return NO;
  }
  if (strcmp(flag, "--style") == 0) {
    if (strcmp(value, "kdirstat") == 0) {
      ExportOptions.style = LDTreemapStyleKDirStat;
      return YES;
    }
    if (strcmp(value, "sequoia") == 0) {
      ExportOptions.style = LDTreemapStyleSequoiaView;
      return YES;
    }
  }
  return NO;
}

// Renders the production treemap (layout, rank colors and cushions) to a PPM.
static BOOL WritePPM(LDFileNode *root, int width, int height, const char *path)
{
  NSArray *stats = [LDExtensionStats sortedStatsForRootNode:root metric:LDSizeMetricPhysical];
  LDTreemap *treemap = [[LDTreemap alloc] initWithRootNode:root
                                                    metric:LDSizeMetricPhysical
                                                     width:width
                                                    height:height
                                                   options:ExportOptions];
  NSData *rgba = [treemap renderRGBAWithColorIndexes:[LDExtensionStats colorIndexMapForSortedStats:stats]];
  FILE *file = fopen(path, "wb");
  if (!file) {
    return NO;
  }
  fprintf(file, "P6\n%d %d\n255\n", width, height);
  const uint8_t *pixels = [rgba bytes];
  NSUInteger i = 0;
  for (i = 0; i < (NSUInteger)width * (NSUInteger)height; i++) {
    fwrite(pixels + i * 4, 1, 3, file);
  }
  fclose(file);
  return YES;
}

static NSDictionary *FixtureNamed(NSDictionary *spec, NSString *name)
{
  NSArray *fixtures = [spec objectForKey:@"fixtures"];
  NSEnumerator *enumerator = [fixtures objectEnumerator];
  NSDictionary *fixture = nil;
  while ((fixture = [enumerator nextObject])) {
    if ([[fixture objectForKey:@"name"] isEqualToString:name]) {
      return fixture;
    }
  }
  return nil;
}

static unsigned long long NodeSizeFromSpec(NSDictionary *spec)
{
  NSArray *children = [spec objectForKey:@"children"];
  if ([children count] > 0) {
    unsigned long long total = 0;
    NSEnumerator *enumerator = [children objectEnumerator];
    NSDictionary *child = nil;
    while ((child = [enumerator nextObject])) {
      total += NodeSizeFromSpec(child);
    }
    return total;
  }
  NSNumber *size = [spec objectForKey:@"size"];
  return size ? [size unsignedLongLongValue] : 0;
}

static LDFileNode *NodeFromSpec(NSDictionary *spec, NSString *parentPath)
{
  NSString *name = [spec objectForKey:@"name"];
  NSString *path = parentPath ? [parentPath stringByAppendingPathComponent:name] : name;
  NSArray *children = [spec objectForKey:@"children"];
  LDFileNodeKind kind = ([children count] > 0) ? LDFileNodeKindDirectory : LDFileNodeKindFile;
  unsigned long long size = (kind == LDFileNodeKindDirectory) ? 0 : NodeSizeFromSpec(spec);
  // "space": "free" or "unknown" makes a <Free Space> or <Unknown> item.
  NSString *space = [spec objectForKey:@"space"];
  if ([space isEqualToString:@"free"]) {
    kind = LDFileNodeKindFreeSpace;
  } else if ([space isEqualToString:@"unknown"]) {
    kind = LDFileNodeKindUnknown;
  }
  LDFileNode *node = [LDFileNode nodeWithPath:path kind:kind size:size];

  NSEnumerator *enumerator = [children objectEnumerator];
  NSDictionary *child = nil;
  while ((child = [enumerator nextObject])) {
    [node addChild:NodeFromSpec(child, path)];
  }
  [node recalculateAggregateSize];
  return node;
}

static NSDictionary *DictionaryForItem(LDTreemapItem *item)
{
  NSRect rect = [item rect];
  LDFileNode *node = [item node];
  return [NSDictionary dictionaryWithObjectsAndKeys:
          [node path], @"path",
          [node displayName], @"name",
          [item extensionKey] ? [item extensionKey] : @"<none>", @"ext",
          [NSNumber numberWithUnsignedLongLong:[node aggregateSize]], @"size",
          [NSNumber numberWithUnsignedInteger:[item depth]], @"depth",
          [NSArray arrayWithObjects:
           [NSNumber numberWithDouble:rect.origin.x],
           [NSNumber numberWithDouble:rect.origin.y],
           [NSNumber numberWithDouble:rect.size.width],
           [NSNumber numberWithDouble:rect.size.height],
           nil], @"rect",
          nil];
}

static int RunExporter(int argc, const char *argv[])
{
  ExportOptions = LDTreemapDefaultOptions();
  while (argc >= 3 && strncmp(argv[1], "--", 2) == 0 && strcmp(argv[1], "--path") != 0) {
    if (!ParseOption(argv[1], argv[2])) {
      PrintUsage();
      return 2;
    }
    argv[2] = argv[0];
    argv += 2;
    argc -= 2;
  }
  const char *ppmPath = NULL;
  if (argc >= 3 && strcmp(argv[argc - 2], "--ppm") == 0) {
    ppmPath = argv[argc - 1];
    argc -= 2;
  }
  if (argc != 5 && argc != 4) {
    PrintUsage();
    return 2;
  }

  LDFileNode *root = nil;
  double width = 0.0;
  double height = 0.0;
  NSError *error = nil;

  if (argc == 4 && strcmp(argv[1], "--path") == 0) {
    NSString *scanPath = [NSString stringWithUTF8String:argv[2]];
    width = atof(argv[3]);
    height = width;
    const char *heightEnv = getenv("LINDIRSTAT_TREEMAP_HEIGHT");
    if (heightEnv) {
      height = atof(heightEnv);
    }
    LDScanner *scanner = [[LDScanner alloc] init];
    LDScanSession *session = [[LDScanSession alloc] init];
    root = [scanner scanPath:scanPath session:session];
    if (!root) {
      fprintf(stderr, "could not scan path: %s\n", argv[2]);
      return 1;
    }
  } else if (argc == 5) {
    NSString *specPath = [NSString stringWithUTF8String:argv[1]];
    NSString *fixtureName = [NSString stringWithUTF8String:argv[2]];
    width = atof(argv[3]);
    height = atof(argv[4]);

    NSData *data = [NSData dataWithContentsOfFile:specPath];
    if (!data) {
      fprintf(stderr, "could not read fixture spec: %s\n", argv[1]);
      return 1;
    }

    NSDictionary *spec = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (!spec) {
      fprintf(stderr, "could not parse fixture spec: %s\n", [[error description] UTF8String]);
      return 1;
    }

    NSDictionary *fixture = FixtureNamed(spec, fixtureName);
    if (!fixture) {
      fprintf(stderr, "fixture not found: %s\n", argv[2]);
      return 1;
    }
    root = NodeFromSpec([fixture objectForKey:@"tree"], nil);
    [root sortChildrenByMetric:LDSizeMetricPhysical];
  } else {
    PrintUsage();
    return 2;
  }

  if (ppmPath && !WritePPM(root, (int)width, (int)height, ppmPath)) {
    fprintf(stderr, "could not write %s\n", ppmPath);
    return 1;
  }

  NSArray *items = [LDTreemapLayout layoutItemsForRootNode:root
                                                    metric:LDSizeMetricPhysical
                                                    inRect:NSMakeRect(0.0, 0.0, width, height)
                                                   options:ExportOptions];
  NSMutableArray *outputItems = [NSMutableArray array];
  NSEnumerator *enumerator = [items objectEnumerator];
  LDTreemapItem *item = nil;
  while ((item = [enumerator nextObject])) {
    [outputItems addObject:DictionaryForItem(item)];
  }

  NSData *output = [NSJSONSerialization dataWithJSONObject:outputItems options:0 error:&error];
  if (!output) {
    fprintf(stderr, "could not encode treemap JSON: %s\n", [[error description] UTF8String]);
    return 1;
  }
  fwrite([output bytes], 1, [output length], stdout);
  fputc('\n', stdout);

  return 0;
}

int main(int argc, const char *argv[])
{
  @autoreleasepool {
    return RunExporter(argc, argv);
  }
}
