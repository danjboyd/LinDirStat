#import <Foundation/Foundation.h>
#import "LDFileNode.h"
#import "LDScanner.h"
#import "LDScanSession.h"
#import "LDTreemapItem.h"
#import "LDTreemapLayout.h"

static void PrintUsage(void)
{
  fprintf(stderr, "usage: windirstat-parity-exporter fixtures.json fixture-name width height\n");
  fprintf(stderr, "       windirstat-parity-exporter --path path width height\n");
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

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  if (argc != 5 && argc != 4) {
    PrintUsage();
    [pool drain];
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
    LDScanner *scanner = [[[LDScanner alloc] init] autorelease];
    LDScanSession *session = [[[LDScanSession alloc] init] autorelease];
    root = [scanner scanPath:scanPath session:session];
    if (!root) {
      fprintf(stderr, "could not scan path: %s\n", argv[2]);
      [pool drain];
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
      [pool drain];
      return 1;
    }

    NSDictionary *spec = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (!spec) {
      fprintf(stderr, "could not parse fixture spec: %s\n", [[error description] UTF8String]);
      [pool drain];
      return 1;
    }

    NSDictionary *fixture = FixtureNamed(spec, fixtureName);
    if (!fixture) {
      fprintf(stderr, "fixture not found: %s\n", argv[2]);
      [pool drain];
      return 1;
    }
    root = NodeFromSpec([fixture objectForKey:@"tree"], nil);
  } else {
    PrintUsage();
    [pool drain];
    return 2;
  }

  NSArray *items = [LDTreemapLayout layoutItemsForRootNode:root inRect:NSMakeRect(0.0, 0.0, width, height)];
  NSMutableArray *outputItems = [NSMutableArray array];
  NSEnumerator *enumerator = [items objectEnumerator];
  LDTreemapItem *item = nil;
  while ((item = [enumerator nextObject])) {
    [outputItems addObject:DictionaryForItem(item)];
  }

  NSData *output = [NSJSONSerialization dataWithJSONObject:outputItems options:0 error:&error];
  if (!output) {
    fprintf(stderr, "could not encode treemap JSON: %s\n", [[error description] UTF8String]);
    [pool drain];
    return 1;
  }
  fwrite([output bytes], 1, [output length], stdout);
  fputc('\n', stdout);

  [pool drain];
  return 0;
}
