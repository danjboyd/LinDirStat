#import "LDCommandLine.h"
#import "LDCSV.h"
#import "LDDuplicateFinder.h"
#import "LDFileNode.h"
#import "LDScanner.h"
#import "LDScanOptions.h"
#import "LDScanSession.h"

static NSString *const LDFlagSaveToCSV = @"savetocsv";
static NSString *const LDFlagSaveDuplicatesToCSV = @"savedupestocsv";
static NSString *const LDFlagLoadFromCSV = @"loadfromcsv";

@implementation LDCommandLine

+ (LDCommandLine *)commandLineWithArguments:(NSArray *)arguments currentDirectory:(NSString *)currentDirectory
{
  LDCommandLine *commandLine = [[LDCommandLine alloc] init];
  [commandLine parseArguments:arguments currentDirectory:currentDirectory];
  return commandLine;
}

+ (LDCommandLine *)processCommandLine
{
  return [self commandLineWithArguments:[[NSProcessInfo processInfo] arguments]
                       currentDirectory:[[NSFileManager defaultManager] currentDirectoryPath]];
}

- (id)init
{
  self = [super init];
  if (self) {
    _scanPaths = [[NSMutableArray alloc] init];
    _ignoredPaths = [[NSMutableArray alloc] init];
  }
  return self;
}

- (NSArray *)scanPaths { return _scanPaths; }
- (NSArray *)ignoredPaths { return _ignoredPaths; }
- (NSString *)saveToCSVPath { return _saveToCSVPath; }
- (NSString *)saveDuplicatesToCSVPath { return _saveDuplicatesToCSVPath; }
- (NSString *)loadFromCSVPath { return _loadFromCSVPath; }
- (NSString *)errorMessage { return _errorMessage; }
- (BOOL)isHeadless { return _headless; }

// The lowercased name of a WinDirStat flag ("--savetocsv", "-SaveToCSV",
// "/savetocsv"), or nil. WinDirStat 2.6's names (34daeec3: /saveto,
// /savedupesto, /loadfrom, for CSV or JSON) give the same flags.
+ (NSString *)flagNameOfArgument:(NSString *)argument
{
  NSString *name = nil;
  if ([argument hasPrefix:@"--"]) {
    name = [argument substringFromIndex:2];
  } else if ([argument hasPrefix:@"-"] || [argument hasPrefix:@"/"]) {
    name = [argument substringFromIndex:1];
  } else {
    return nil;
  }
  name = [name lowercaseString];
  NSDictionary *renamed = @{@"saveto": LDFlagSaveToCSV, @"savedupesto": LDFlagSaveDuplicatesToCSV, @"loadfrom": LDFlagLoadFromCSV};
  if ([renamed objectForKey:name]) {
    return [renamed objectForKey:name];
  }
  NSArray *flags = [NSArray arrayWithObjects:LDFlagSaveToCSV, LDFlagSaveDuplicatesToCSV, LDFlagLoadFromCSV, nil];
  return [flags containsObject:name] ? name : nil;
}

+ (NSString *)absolutePath:(NSString *)path currentDirectory:(NSString *)currentDirectory
{
  NSString *expanded = [path stringByExpandingTildeInPath];
  if (![expanded isAbsolutePath]) {
    expanded = [currentDirectory stringByAppendingPathComponent:expanded];
  }
  return [expanded stringByStandardizingPath];
}

- (void)setFlag:(NSString *)flag value:(NSString *)value
{
  if ([flag isEqualToString:LDFlagSaveToCSV]) {
    _saveToCSVPath = value;
  } else if ([flag isEqualToString:LDFlagSaveDuplicatesToCSV]) {
    _saveDuplicatesToCSVPath = value;
  } else {
    _loadFromCSVPath = value;
  }
}

- (void)addScanPath:(NSString *)argument currentDirectory:(NSString *)currentDirectory
{
  NSString *path = [LDCommandLine absolutePath:argument currentDirectory:currentDirectory];
  BOOL isDirectory = NO;
  if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
    [_scanPaths addObject:path];
  } else {
    [_ignoredPaths addObject:argument];
  }
}

- (void)parseArguments:(NSArray *)arguments currentDirectory:(NSString *)currentDirectory
{
  NSUInteger count = [arguments count];
  NSUInteger index = 1;
  while (index < count) {
    NSString *argument = [arguments objectAtIndex:index];
    NSString *flag = [LDCommandLine flagNameOfArgument:argument];
    if (flag) {
      _headless = _headless || ![flag isEqualToString:LDFlagLoadFromCSV];
      if (index + 1 >= count) {
        _errorMessage = [NSString stringWithFormat:@"%@ needs a file name", argument];
        return;
      }
      [self setFlag:flag value:[LDCommandLine absolutePath:[arguments objectAtIndex:index + 1]
                                          currentDirectory:currentDirectory]];
      index += 2;
    } else if ([argument hasPrefix:@"--"]) {
      index++;
    } else if ([argument hasPrefix:@"-"]) {
      index += 2; // A GNUstep or Cocoa "-Key value" default.
    } else {
      [self addScanPath:argument currentDirectory:currentDirectory];
      index++;
    }
  }
}

@end

@implementation LDCommandLineExport

+ (int)runCommandLine:(LDCommandLine *)commandLine
          scanOptions:(LDScanOptions *)options
         includeOwner:(BOOL)includeOwner
             messages:(NSMutableArray *)messages
{
  if ([commandLine errorMessage]) {
    [messages addObject:[commandLine errorMessage]];
    return 1;
  }
  for (NSString *path in [commandLine ignoredPaths]) {
    [messages addObject:[NSString stringWithFormat:@"Not a folder, ignored: %@", path]];
  }
  if ([[commandLine scanPaths] count] == 0) {
    [messages addObject:@"No folder to scan"];
    return 1;
  }
  NSError *error = nil;
  if (![options validateWithError:&error]) {
    [messages addObject:[error localizedDescription]];
    return 1;
  }

  NSString *duplicatesPath = [commandLine saveDuplicatesToCSVPath];
  LDScanner *scanner = [[LDScanner alloc] init];
  [scanner setScanOptions:options];
  [scanner setFindsDuplicates:duplicatesPath != nil];
  LDScanSession *session = [[LDScanSession alloc] init];
  LDFileNode *root = [scanner scanPaths:[commandLine scanPaths] session:session];

  BOOL succeeded = YES;
  NSString *resultsPath = [commandLine saveToCSVPath];
  if (resultsPath && ![LDCSV writeTree:root toPath:resultsPath includeOwner:includeOwner error:&error]) {
    [messages addObject:[NSString stringWithFormat:@"%@: %@", resultsPath, [error localizedDescription]]];
    succeeded = NO;
  }
  if (duplicatesPath) {
    LDDuplicateCollector *collector = [session duplicateCollector];
    [collector waitUntilFinished];
    if (![LDCSV writeDuplicateGroups:[collector groups] toPath:duplicatesPath error:&error]) {
      [messages addObject:[NSString stringWithFormat:@"%@: %@", duplicatesPath, [error localizedDescription]]];
      succeeded = NO;
    }
  }
  return succeeded ? 0 : 1;
}

@end
