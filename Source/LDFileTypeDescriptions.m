#import "LDFileTypeDescriptions.h"

@implementation LDFileTypeDescriptions

+ (LDFileTypeDescriptions *)sharedDescriptions
{
  static LDFileTypeDescriptions *shared = nil;
  if (!shared) {
    shared = [[LDFileTypeDescriptions alloc] initWithMimeDirectory:@"/usr/share/mime"];
  }
  return shared;
}

- (id)initWithMimeDirectory:(NSString *)directory
{
  self = [super init];
  if (self) {
    _mimeDirectory = [directory copy];
    _descriptionsByMimeType = [[NSMutableDictionary alloc] init];
  }
  return self;
}

// globs2 lines are "weight:mime/type:glob[:flags]"; keep the highest-weight
// type for each simple "*.ext" glob.
- (NSDictionary *)mimeTypesByExtension
{
  if (_mimeTypesByExtension) {
    return _mimeTypesByExtension;
  }
  NSMutableDictionary *types = [NSMutableDictionary dictionary];
  NSMutableDictionary *weights = [NSMutableDictionary dictionary];
  NSString *globs = [NSString stringWithContentsOfFile:[_mimeDirectory stringByAppendingPathComponent:@"globs2"]
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
  NSEnumerator *lines = [[globs componentsSeparatedByString:@"\n"] objectEnumerator];
  NSString *line = nil;
  NSCharacterSet *wildcards = [NSCharacterSet characterSetWithCharactersInString:@"*?[]."];
  while ((line = [lines nextObject])) {
    if ([line hasPrefix:@"#"]) {
      continue;
    }
    NSArray *fields = [line componentsSeparatedByString:@":"];
    if ([fields count] < 3) {
      continue;
    }
    NSString *glob = [fields objectAtIndex:2];
    if (![glob hasPrefix:@"*."]) {
      continue;
    }
    NSString *original = [glob substringFromIndex:2];
    NSString *extension = [original lowercaseString];
    BOOL exactCase = [original isEqualToString:extension];
    // A case-sensitive glob ("*.C" for C++) only matches its own case, and
    // extension keys are lowercase.
    BOOL caseSensitive = [fields count] > 3 && [[fields objectAtIndex:3] rangeOfString:@"cs"].location != NSNotFound;
    if ([extension length] == 0 || (caseSensitive && !exactCase)
        || [extension rangeOfCharacterFromSet:wildcards].location != NSNotFound) {
      continue;
    }
    // Higher weight wins; at equal weight a glob already in lowercase beats
    // one that only matches after folding case ("*.c" over "*.C").
    NSInteger score = [[fields objectAtIndex:0] integerValue] * 2 + (exactCase ? 1 : 0);
    NSNumber *existing = [weights objectForKey:extension];
    if (!existing || score > [existing integerValue]) {
      [weights setObject:[NSNumber numberWithInteger:score] forKey:extension];
      [types setObject:[fields objectAtIndex:1] forKey:extension];
    }
  }
  _mimeTypesByExtension = types;
  return _mimeTypesByExtension;
}

- (NSString *)unescapedXMLText:(NSString *)text
{
  NSString *result = text;
  result = [result stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
  result = [result stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
  result = [result stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
  result = [result stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"];
  return [result stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
}

// The untranslated <comment> of the type's XML file.
- (NSString *)descriptionForMimeType:(NSString *)mimeType
{
  id cached = [_descriptionsByMimeType objectForKey:mimeType];
  if (cached) {
    return cached == [NSNull null] ? nil : cached;
  }
  NSString *path = [[_mimeDirectory stringByAppendingPathComponent:mimeType] stringByAppendingPathExtension:@"xml"];
  NSString *xml = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
  NSString *description = nil;
  NSRange start = [xml rangeOfString:@"<comment>"];
  if (start.location != NSNotFound) {
    NSUInteger from = NSMaxRange(start);
    NSRange end = [xml rangeOfString:@"</comment>" options:0 range:NSMakeRange(from, [xml length] - from)];
    if (end.location != NSNotFound) {
      description = [self unescapedXMLText:[xml substringWithRange:NSMakeRange(from, end.location - from)]];
    }
  }
  [_descriptionsByMimeType setObject:description ? (id)description : (id)[NSNull null] forKey:mimeType];
  return description;
}

- (NSString *)descriptionForExtensionKey:(NSString *)extensionKey
{
  if ([extensionKey length] == 0 || [extensionKey isEqualToString:@"<none>"]) {
    return nil;
  }
  NSString *mimeType = [[self mimeTypesByExtension] objectForKey:extensionKey];
  return mimeType ? [self descriptionForMimeType:mimeType] : nil;
}

@end
