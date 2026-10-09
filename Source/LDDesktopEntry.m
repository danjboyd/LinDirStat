#import "LDDesktopEntry.h"
#import "LDDesktop.h"

@implementation LDDesktopEntry

+ (LDDesktopEntry *)entryWithContentsOfFile:(NSString *)path identifier:(NSString *)identifier
{
  NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
  return text ? [self entryWithString:text filePath:path identifier:identifier] : nil;
}

// Keys of the [Desktop Entry] group; other groups (actions) are skipped and
// the first occurrence of a key wins.
+ (LDDesktopEntry *)entryWithString:(NSString *)text filePath:(NSString *)path identifier:(NSString *)identifier
{
  NSMutableDictionary *values = [NSMutableDictionary dictionary];
  BOOL inEntry = NO;
  BOOL sawEntry = NO;
  for (NSString *rawLine in [text componentsSeparatedByString:@"\n"]) {
    NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([line length] == 0 || [line hasPrefix:@"#"]) {
      continue;
    }
    if ([line hasPrefix:@"["]) {
      inEntry = [line isEqualToString:@"[Desktop Entry]"];
      sawEntry = sawEntry || inEntry;
      continue;
    }
    if (!inEntry) {
      continue;
    }
    NSRange equals = [line rangeOfString:@"="];
    if (equals.location == NSNotFound) {
      continue;
    }
    NSString *key = [[line substringToIndex:equals.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *value = [[line substringFromIndex:NSMaxRange(equals)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([key length] > 0 && ![values objectForKey:key]) {
      [values setObject:value forKey:key];
    }
  }
  if (!sawEntry) {
    return nil;
  }
  LDDesktopEntry *entry = [[LDDesktopEntry alloc] init];
  entry->_identifier = [identifier copy];
  entry->_filePath = [path copy];
  entry->_values = values;
  return entry;
}

- (NSString *)identifier { return _identifier; }
- (NSString *)filePath { return _filePath; }

+ (NSString *)unescapedValue:(NSString *)value
{
  if ([value rangeOfString:@"\\"].location == NSNotFound) {
    return value;
  }
  NSMutableString *result = [NSMutableString string];
  NSUInteger length = [value length];
  for (NSUInteger i = 0; i < length; i++) {
    unichar c = [value characterAtIndex:i];
    if (c == '\\' && i + 1 < length) {
      unichar next = [value characterAtIndex:++i];
      switch (next) {
        case 's': [result appendString:@" "]; break;
        case 'n': [result appendString:@"\n"]; break;
        case 't': [result appendString:@"\t"]; break;
        case 'r': [result appendString:@"\r"]; break;
        case '\\': [result appendString:@"\\"]; break;
        default: [result appendFormat:@"\\%C", next]; break;
      }
    } else {
      [result appendFormat:@"%C", c];
    }
  }
  return result;
}

- (NSString *)stringForKey:(NSString *)key
{
  NSString *value = [_values objectForKey:key];
  return value ? [LDDesktopEntry unescapedValue:value] : nil;
}

- (BOOL)booleanForKey:(NSString *)key
{
  return [[_values objectForKey:key] isEqualToString:@"true"];
}

- (NSString *)name
{
  return [self stringForKey:@"Name"] ?: [_identifier stringByDeletingPathExtension];
}

- (NSString *)iconName { return [self stringForKey:@"Icon"]; }
- (NSString *)exec { return [self stringForKey:@"Exec"]; }
- (BOOL)isApplication { return [[self stringForKey:@"Type"] isEqualToString:@"Application"]; }
- (BOOL)isHidden { return [self booleanForKey:@"Hidden"]; }
- (BOOL)runsInTerminal { return [self booleanForKey:@"Terminal"]; }

- (NSArray *)mimeTypes
{
  NSMutableArray *types = [NSMutableArray array];
  for (NSString *type in [[self stringForKey:@"MimeType"] componentsSeparatedByString:@";"]) {
    NSString *trimmed = [type stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmed length] > 0) {
      [types addObject:trimmed];
    }
  }
  return types;
}

- (BOOL)acceptsFiles
{
  for (NSString *argument in [LDDesktopEntry argumentsForExec:[self exec]]) {
    for (NSString *code in @[@"%f", @"%F", @"%u", @"%U"]) {
      if ([argument rangeOfString:code].location != NSNotFound) {
        return YES;
      }
    }
  }
  return NO;
}

- (BOOL)isUsableForOpening
{
  if (![self isApplication] || [self isHidden] || ![self acceptsFiles]) {
    return NO;
  }
  NSString *tryExec = [self stringForKey:@"TryExec"];
  if ([tryExec length] > 0 && ![LDDesktop pathOfExecutable:tryExec]) {
    return NO;
  }
  NSString *program = [[LDDesktopEntry argumentsForExec:[self exec]] firstObject];
  return [program length] > 0 && [LDDesktop pathOfExecutable:program] != nil;
}

static BOOL LDIsQuotedEscape(unichar c)
{
  return c == '"' || c == '`' || c == '$' || c == '\\';
}

+ (NSArray *)argumentsForExec:(NSString *)exec
{
  if (!exec) {
    return nil;
  }
  NSMutableArray *arguments = [NSMutableArray array];
  NSMutableString *current = nil;
  BOOL quoted = NO;
  NSUInteger length = [exec length];
  for (NSUInteger i = 0; i < length; i++) {
    unichar c = [exec characterAtIndex:i];
    if (quoted) {
      if (c == '"') {
        quoted = NO;
      } else if (c == '\\' && i + 1 < length && LDIsQuotedEscape([exec characterAtIndex:i + 1])) {
        [current appendFormat:@"%C", [exec characterAtIndex:++i]];
      } else {
        [current appendFormat:@"%C", c];
      }
      continue;
    }
    if (c == ' ' || c == '\t') {
      if (current) {
        [arguments addObject:current];
        current = nil;
      }
      continue;
    }
    if (!current) {
      current = [NSMutableString string];
    }
    if (c == '"') {
      quoted = YES;
    } else if (c == '\\' && i + 1 < length) {
      [current appendFormat:@"%C", [exec characterAtIndex:++i]];
    } else {
      [current appendFormat:@"%C", c];
    }
  }
  if (quoted) {
    return nil;
  }
  if (current) {
    [arguments addObject:current];
  }
  return arguments;
}

static void LDAppendString(NSMutableData *data, NSString *string)
{
  const char *bytes = [string UTF8String];
  [data appendBytes:bytes length:strlen(bytes)];
}

// One argument with its field codes expanded for path (nil when there is no
// path). Returns nil when the argument only held codes that expand to
// nothing, so it is dropped.
- (id)expandArgument:(NSString *)argument path:(NSData *)path
{
  NSMutableData *result = [NSMutableData data];
  BOOL insertedPath = NO;
  BOOL hadCode = NO;
  NSUInteger length = [argument length];
  NSUInteger start = 0;
  for (NSUInteger i = 0; i < length; i++) {
    if ([argument characterAtIndex:i] != '%' || i + 1 >= length) {
      continue;
    }
    LDAppendString(result, [argument substringWithRange:NSMakeRange(start, i - start)]);
    unichar code = [argument characterAtIndex:++i];
    start = i + 1;
    hadCode = YES;
    switch (code) {
      case 'f':
      case 'F':
        if (path) {
          [result appendData:path];
          insertedPath = YES;
        }
        break;
      case 'u':
      case 'U':
        if (path) {
          LDAppendString(result, [LDDesktop fileURIForPath:path]);
        }
        break;
      case 'c':
        LDAppendString(result, [self name]);
        break;
      case 'k':
        LDAppendString(result, _filePath ?: @"");
        break;
      case '%':
        [result appendBytes:"%" length:1];
        break;
      default:
        // %i inside an argument, and the deprecated %d %D %n %N %v %m.
        break;
    }
  }
  LDAppendString(result, [argument substringFromIndex:start]);
  if ([result length] == 0 && hadCode) {
    return nil;
  }
  if (insertedPath) {
    return result;
  }
  return [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding];
}

- (NSArray *)commandWithArguments:(NSArray *)arguments paths:(NSArray *)paths single:(NSData *)single
{
  NSMutableArray *command = [NSMutableArray array];
  for (NSString *argument in arguments) {
    if ([argument isEqualToString:@"%F"]) {
      [command addObjectsFromArray:paths];
    } else if ([argument isEqualToString:@"%U"]) {
      for (NSData *path in paths) {
        [command addObject:[LDDesktop fileURIForPath:path]];
      }
    } else if ([argument isEqualToString:@"%i"]) {
      NSString *icon = [self iconName];
      if ([icon length] > 0) {
        [command addObject:@"--icon"];
        [command addObject:icon];
      }
    } else {
      id expanded = [self expandArgument:argument path:single];
      if (expanded) {
        [command addObject:expanded];
      }
    }
  }
  return command;
}

- (NSArray *)commandsForPaths:(NSArray *)paths
{
  NSArray *arguments = [LDDesktopEntry argumentsForExec:[self exec]];
  if ([arguments count] == 0) {
    return @[];
  }
  BOOL takesList = [arguments containsObject:@"%F"] || [arguments containsObject:@"%U"];
  if (takesList || [paths count] == 0) {
    return @[[self commandWithArguments:arguments paths:paths single:[paths firstObject]]];
  }
  NSMutableArray *commands = [NSMutableArray array];
  for (NSData *path in paths) {
    [commands addObject:[self commandWithArguments:arguments paths:@[path] single:path]];
  }
  return commands;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"<LDDesktopEntry %@>", _identifier];
}

@end
