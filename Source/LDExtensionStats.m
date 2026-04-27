#import "LDExtensionStats.h"
#import "LDFileNode.h"

@implementation LDExtensionStats

+ (NSString *)extensionKeyForFilename:(NSString *)filename
{
  NSString *name = [filename lastPathComponent];
  if ([name length] == 0 || ([name hasPrefix:@"."] && [[name pathExtension] length] == 0)) {
    return @"<none>";
  }

  NSString *extension = [name pathExtension];
  if ([extension length] == 0) {
    return @"<none>";
  }
  return [extension lowercaseString];
}

+ (void)collectNode:(LDFileNode *)node intoStats:(NSMutableDictionary *)stats
{
  if ([node kind] != LDFileNodeKindDirectory) {
    NSString *key = [self extensionKeyForFilename:[node displayName]];
    LDExtensionStats *entry = [stats objectForKey:key];
    if (!entry) {
      entry = [[[LDExtensionStats alloc] initWithExtensionKey:key] autorelease];
      [stats setObject:entry forKey:key];
    }
    [entry addBytes:[node size]];
    return;
  }

  NSEnumerator *enumerator = [[node children] objectEnumerator];
  LDFileNode *child = nil;
  while ((child = [enumerator nextObject])) {
    [self collectNode:child intoStats:stats];
  }
}

+ (NSArray *)sortedStatsForRootNode:(LDFileNode *)rootNode
{
  NSMutableDictionary *stats = [NSMutableDictionary dictionary];
  [self collectNode:rootNode intoStats:stats];
  return [[stats allValues] sortedArrayUsingSelector:@selector(compareByBytesThenName:)];
}

- (id)initWithExtensionKey:(NSString *)extensionKey
{
  self = [super init];
  if (self) {
    _extensionKey = [extensionKey copy];
    if ([extensionKey isEqualToString:@"<none>"]) {
      _displayName = [@"[no extension]" copy];
    } else {
      _displayName = [[@"." stringByAppendingString:extensionKey] copy];
    }
  }
  return self;
}

- (NSString *)extensionKey { return _extensionKey; }
- (NSString *)displayName { return _displayName; }
- (unsigned long long)bytes { return _bytes; }
- (NSUInteger)fileCount { return _fileCount; }

- (double)percentageOfTotal:(unsigned long long)totalBytes
{
  if (totalBytes == 0) {
    return 0.0;
  }
  return ((double)_bytes / (double)totalBytes) * 100.0;
}

- (void)addBytes:(unsigned long long)bytes
{
  _bytes += bytes;
  _fileCount += 1;
}

- (NSComparisonResult)compareByBytesThenName:(LDExtensionStats *)other
{
  if (_bytes > [other bytes]) {
    return NSOrderedAscending;
  }
  if (_bytes < [other bytes]) {
    return NSOrderedDescending;
  }
  return [_extensionKey compare:[other extensionKey]];
}

- (void)dealloc
{
  [_extensionKey release];
  [_displayName release];
  [super dealloc];
}

@end
