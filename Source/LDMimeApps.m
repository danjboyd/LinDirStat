#import "LDMimeApps.h"
#import "LDDesktopEntry.h"

static NSString *const LDDefaultsSection = @"Default Applications";
static NSString *const LDAddedSection = @"Added Associations";
static NSString *const LDRemovedSection = @"Removed Associations";

@implementation LDMimeApps

+ (NSString *)environment:(NSDictionary *)environment value:(NSString *)key fallback:(NSString *)fallback
{
  NSString *value = [environment objectForKey:key];
  return [value length] > 0 ? value : fallback;
}

+ (NSArray *)directoriesInList:(NSString *)list
{
  NSMutableArray *directories = [NSMutableArray array];
  for (NSString *directory in [list componentsSeparatedByString:@":"]) {
    if ([directory length] > 0) {
      [directories addObject:directory];
    }
  }
  return directories;
}

+ (NSArray *)dataDirectoriesForEnvironment:(NSDictionary *)environment
{
  NSString *home = [environment objectForKey:@"HOME"] ?: NSHomeDirectory();
  NSString *dataHome = [self environment:environment value:@"XDG_DATA_HOME" fallback:[home stringByAppendingPathComponent:@".local/share"]];
  NSString *dataDirs = [self environment:environment value:@"XDG_DATA_DIRS" fallback:@"/usr/local/share:/usr/share"];
  return [@[dataHome] arrayByAddingObjectsFromArray:[self directoriesInList:dataDirs]];
}

+ (NSArray *)applicationDirectoriesForEnvironment:(NSDictionary *)environment
{
  NSMutableArray *directories = [NSMutableArray array];
  for (NSString *directory in [self dataDirectoriesForEnvironment:environment]) {
    [directories addObject:[directory stringByAppendingPathComponent:@"applications"]];
  }
  return directories;
}

// $desktop-mimeapps.list before mimeapps.list in each folder: the user's
// configuration, the system's, then the (deprecated) data folders.
+ (NSArray *)mimeappsListPathsForEnvironment:(NSDictionary *)environment
{
  NSString *home = [environment objectForKey:@"HOME"] ?: NSHomeDirectory();
  NSString *configHome = [self environment:environment value:@"XDG_CONFIG_HOME" fallback:[home stringByAppendingPathComponent:@".config"]];
  NSString *configDirs = [self environment:environment value:@"XDG_CONFIG_DIRS" fallback:@"/etc/xdg"];
  NSMutableArray *folders = [NSMutableArray arrayWithObject:configHome];
  [folders addObjectsFromArray:[self directoriesInList:configDirs]];
  [folders addObjectsFromArray:[self applicationDirectoriesForEnvironment:environment]];
  NSArray *desktops = [[[environment objectForKey:@"XDG_CURRENT_DESKTOP"] lowercaseString] componentsSeparatedByString:@":"];
  NSMutableArray *paths = [NSMutableArray array];
  for (NSString *folder in folders) {
    for (NSString *desktop in desktops) {
      if ([desktop length] > 0) {
        [paths addObject:[folder stringByAppendingPathComponent:[desktop stringByAppendingString:@"-mimeapps.list"]]];
      }
    }
    [paths addObject:[folder stringByAppendingPathComponent:@"mimeapps.list"]];
  }
  return paths;
}

- (id)initWithApplicationDirectories:(NSArray *)applicationDirectories
                  mimeappsListPaths:(NSArray *)listPaths
                      mimeDirectory:(NSString *)mimeDirectory
{
  self = [super init];
  if (self) {
    _applicationDirectories = [applicationDirectories copy];
    _listPaths = [listPaths copy];
    _mimeDirectory = [mimeDirectory copy];
  }
  return self;
}

#pragma mark - Loading

- (NSString *)currentSignature
{
  NSFileManager *manager = [NSFileManager defaultManager];
  NSMutableArray *paths = [NSMutableArray arrayWithArray:_applicationDirectories];
  [paths addObjectsFromArray:_listPaths];
  if (_mimeDirectory) {
    [paths addObject:[_mimeDirectory stringByAppendingPathComponent:@"subclasses"]];
  }
  NSMutableString *signature = [NSMutableString string];
  for (NSString *path in paths) {
    NSDate *date = [[manager attributesOfItemAtPath:path error:NULL] fileModificationDate];
    [signature appendFormat:@"%f;", date ? [date timeIntervalSince1970] : -1.0];
  }
  return signature;
}

- (void)loadApplicationDirectory:(NSString *)directory
{
  NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:directory];
  NSMutableArray *relativePaths = [NSMutableArray array];
  NSString *relative = nil;
  while ((relative = [enumerator nextObject])) {
    if ([[relative pathExtension] isEqualToString:@"desktop"]) {
      [relativePaths addObject:relative];
    }
  }
  [relativePaths sortUsingSelector:@selector(compare:)];
  for (NSString *path in relativePaths) {
    // Desktop file IDs name subfolders with dashes ("kde4/a.desktop" is
    // "kde4-a.desktop"); a higher-precedence folder hides the same ID below.
    NSString *identifier = [path stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    if ([_entries objectForKey:identifier]) {
      continue;
    }
    LDDesktopEntry *entry = [LDDesktopEntry entryWithContentsOfFile:[directory stringByAppendingPathComponent:path]
                                                         identifier:identifier];
    if (!entry) {
      continue;
    }
    [_entries setObject:entry forKey:identifier];
    if ([entry isHidden]) {
      continue;
    }
    for (NSString *type in [entry mimeTypes]) {
      NSMutableArray *identifiers = [_implicit objectForKey:type];
      if (!identifiers) {
        identifiers = [NSMutableArray array];
        [_implicit setObject:identifiers forKey:type];
      }
      [identifiers addObject:identifier];
    }
  }
}

// { section: { type: [desktop IDs] } } of one mimeapps.list.
- (NSDictionary *)parseListAtPath:(NSString *)path
{
  NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
  if (!text) {
    return nil;
  }
  NSMutableDictionary *sections = [NSMutableDictionary dictionary];
  NSMutableDictionary *current = nil;
  for (NSString *rawLine in [text componentsSeparatedByString:@"\n"]) {
    NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([line length] == 0 || [line hasPrefix:@"#"]) {
      continue;
    }
    if ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) {
      NSString *name = [line substringWithRange:NSMakeRange(1, [line length] - 2)];
      current = [sections objectForKey:name];
      if (!current) {
        current = [NSMutableDictionary dictionary];
        [sections setObject:current forKey:name];
      }
      continue;
    }
    NSRange equals = [line rangeOfString:@"="];
    if (!current || equals.location == NSNotFound) {
      continue;
    }
    NSString *type = [[line substringToIndex:equals.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *identifiers = [NSMutableArray array];
    for (NSString *identifier in [[line substringFromIndex:NSMaxRange(equals)] componentsSeparatedByString:@";"]) {
      NSString *trimmed = [identifier stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      if ([trimmed length] > 0) {
        [identifiers addObject:trimmed];
      }
    }
    if (![current objectForKey:type]) {
      [current setObject:identifiers forKey:type];
    }
  }
  return sections;
}

// "child parent" lines of shared-mime-info's subclasses and aliases files.
- (NSDictionary *)pairsInMimeFile:(NSString *)name multiple:(BOOL)multiple
{
  NSMutableDictionary *pairs = [NSMutableDictionary dictionary];
  if (!_mimeDirectory) {
    return pairs;
  }
  NSString *text = [NSString stringWithContentsOfFile:[_mimeDirectory stringByAppendingPathComponent:name]
                                             encoding:NSUTF8StringEncoding
                                                error:NULL];
  for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
    NSArray *fields = [line componentsSeparatedByString:@" "];
    if ([fields count] != 2) {
      continue;
    }
    NSString *key = [fields objectAtIndex:0];
    NSString *value = [fields objectAtIndex:1];
    if (multiple) {
      NSMutableArray *values = [pairs objectForKey:key] ?: [NSMutableArray array];
      [values addObject:value];
      [pairs setObject:values forKey:key];
    } else {
      [pairs setObject:value forKey:key];
    }
  }
  return pairs;
}

- (void)reloadIfChanged
{
  NSString *signature = [self currentSignature];
  if (_entries && [signature isEqualToString:_signature]) {
    return;
  }
  _signature = signature;
  _entries = [NSMutableDictionary dictionary];
  _implicit = [NSMutableDictionary dictionary];
  _usable = [NSMutableDictionary dictionary];
  for (NSString *directory in _applicationDirectories) {
    [self loadApplicationDirectory:directory];
  }
  NSMutableArray *lists = [NSMutableArray array];
  for (NSString *path in _listPaths) {
    NSDictionary *list = [self parseListAtPath:path];
    if (list) {
      [lists addObject:list];
    }
  }
  _lists = lists;
  _parents = [self pairsInMimeFile:@"subclasses" multiple:YES];
  _aliases = [self pairsInMimeFile:@"aliases" multiple:NO];
}

#pragma mark - Queries

- (void)loadIfNeeded
{
  if (!_entries) {
    [self reloadIfChanged];
  }
}

- (LDDesktopEntry *)entryForIdentifier:(NSString *)identifier
{
  [self loadIfNeeded];
  return [_entries objectForKey:identifier];
}

- (NSArray *)typeWithAncestors:(NSString *)type
{
  [self loadIfNeeded];
  NSString *canonical = [_aliases objectForKey:type] ?: type;
  NSMutableArray *types = [NSMutableArray arrayWithObject:canonical];
  for (NSUInteger i = 0; i < [types count]; i++) {
    for (NSString *parent in [_parents objectForKey:[types objectAtIndex:i]]) {
      if (![types containsObject:parent]) {
        [types addObject:parent];
      }
    }
  }
  if ([canonical hasPrefix:@"text/"] && ![types containsObject:@"text/plain"]) {
    [types addObject:@"text/plain"];
  }
  return types;
}

- (LDDesktopEntry *)usableEntry:(NSString *)identifier
{
  LDDesktopEntry *entry = [_entries objectForKey:identifier];
  if (!entry) {
    return nil;
  }
  // Checking the programs touches the disk; once per load is enough.
  NSNumber *usable = [_usable objectForKey:identifier];
  if (!usable) {
    usable = [NSNumber numberWithBool:[entry isUsableForOpening]];
    [_usable setObject:usable forKey:identifier];
  }
  return [usable boolValue] ? entry : nil;
}

- (LDDesktopEntry *)defaultEntryForType:(NSString *)type
{
  for (NSString *candidate in [self typeWithAncestors:type]) {
    for (NSDictionary *list in _lists) {
      for (NSString *identifier in [[list objectForKey:LDDefaultsSection] objectForKey:candidate]) {
        LDDesktopEntry *entry = [self usableEntry:identifier];
        if (entry) {
          return entry;
        }
      }
    }
  }
  return nil;
}

// Removed associations hide a type's applications in their own file, in
// lower-precedence files and in the desktop entries.
- (NSArray *)associatedIdentifiersForType:(NSString *)type
{
  NSMutableArray *identifiers = [NSMutableArray array];
  NSMutableSet *removed = [NSMutableSet set];
  for (NSDictionary *list in _lists) {
    [removed addObjectsFromArray:[[list objectForKey:LDRemovedSection] objectForKey:type]];
    for (NSString *identifier in [[list objectForKey:LDAddedSection] objectForKey:type]) {
      if (![removed containsObject:identifier]) {
        [identifiers addObject:identifier];
      }
    }
  }
  for (NSString *identifier in [_implicit objectForKey:type]) {
    if (![removed containsObject:identifier]) {
      [identifiers addObject:identifier];
    }
  }
  return identifiers;
}

- (NSArray *)entriesForType:(NSString *)type
{
  NSMutableArray *entries = [NSMutableArray array];
  LDDesktopEntry *defaultEntry = [self defaultEntryForType:type];
  if (defaultEntry) {
    [entries addObject:defaultEntry];
  }
  for (NSString *candidate in [self typeWithAncestors:type]) {
    for (NSString *identifier in [self associatedIdentifiersForType:candidate]) {
      LDDesktopEntry *entry = [self usableEntry:identifier];
      if (entry && [entries indexOfObjectIdenticalTo:entry] == NSNotFound) {
        [entries addObject:entry];
      }
    }
  }
  return entries;
}

@end
