#import "LDPreferences.h"

#include <string.h>

NSString *const LDPreferencesDidChangeNotification = @"LDPreferencesDidChangeNotification";

NSString *const LDColumnPhysicalSize = @"physicalSize";
NSString *const LDColumnLogicalSize = @"logicalSize";
NSString *const LDColumnItems = @"items";
NSString *const LDColumnFiles = @"files";
NSString *const LDColumnFolders = @"folders";
NSString *const LDColumnLastChange = @"lastChange";
NSString *const LDColumnAttributes = @"attributes";
NSString *const LDColumnOwner = @"owner";

static const NSUInteger LDCustomCleanupSlots = 10;
enum { LDFileTreeColorSlots = 8 };

// GNOME's palette (blue, red, green, yellow; dark then light) in the order
// of WinDirStat's FileTreeColor0-7.
static const uint32_t LDDefaultFileTreeColors[LDFileTreeColorSlots] = {
  0x1a5fb4, 0xa51d2d, 0x26a269, 0xe5a50a, 0x3584e4, 0xe01b24, 0x33d17a, 0xf6d32d,
};

@implementation LDCustomCleanup

+ (NSString *)defaultTitleForSlot:(NSUInteger)slot
{
  return [NSString stringWithFormat:@"Custom Cleanup #%lu", (unsigned long)slot];
}

- (id)init
{
  self = [super init];
  if (self) {
    _title = @"";
    _commandLine = @"";
  }
  return self;
}

- (id)initWithDictionary:(NSDictionary *)dictionary
{
  self = [self init];
  if (self) {
    _title = [[dictionary objectForKey:@"Title"] copy] ?: @"";
    _commandLine = [[dictionary objectForKey:@"CommandLine"] copy] ?: @"";
    _enabled = [[dictionary objectForKey:@"Enable"] boolValue];
    _worksForMountPoints = [[dictionary objectForKey:@"WorksForDrives"] boolValue];
    _worksForDirectories = [[dictionary objectForKey:@"WorksForDirectories"] boolValue];
    _worksForFiles = [[dictionary objectForKey:@"WorksForFiles"] boolValue];
    _recurseIntoSubdirectories = [[dictionary objectForKey:@"RecurseIntoSubdirectories"] boolValue];
    _askForConfirmation = [[dictionary objectForKey:@"AskForConfirmation"] boolValue];
    _showInTerminal = [[dictionary objectForKey:@"ShowConsoleWindow"] boolValue];
    _waitForCompletion = [[dictionary objectForKey:@"WaitForCompletion"] boolValue];
    _refreshPolicy = (LDRefreshPolicy)[[dictionary objectForKey:@"RefreshPolicy"] intValue];
  }
  return self;
}

- (NSDictionary *)dictionaryRepresentation
{
  return @{
    @"Title": _title ?: @"",
    @"CommandLine": _commandLine ?: @"",
    @"Enable": @(_enabled),
    @"WorksForDrives": @(_worksForMountPoints),
    @"WorksForDirectories": @(_worksForDirectories),
    @"WorksForFiles": @(_worksForFiles),
    @"RecurseIntoSubdirectories": @(_recurseIntoSubdirectories),
    @"AskForConfirmation": @(_askForConfirmation),
    @"ShowConsoleWindow": @(_showInTerminal),
    @"WaitForCompletion": @(_waitForCompletion),
    @"RefreshPolicy": @(_refreshPolicy),
  };
}

- (id)copyWithZone:(NSZone *)zone
{
  (void)zone;
  return [[LDCustomCleanup alloc] initWithDictionary:[self dictionaryRepresentation]];
}

- (NSString *)displayTitleForSlot:(NSUInteger)slot
{
  return [_title length] > 0 ? _title : [LDCustomCleanup defaultTitleForSlot:slot];
}

- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)title { _title = [title copy] ?: @""; }
- (NSString *)commandLine { return _commandLine; }
- (void)setCommandLine:(NSString *)commandLine { _commandLine = [commandLine copy] ?: @""; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)enabled { _enabled = enabled; }
- (BOOL)worksForMountPoints { return _worksForMountPoints; }
- (void)setWorksForMountPoints:(BOOL)flag { _worksForMountPoints = flag; }
- (BOOL)worksForDirectories { return _worksForDirectories; }
- (void)setWorksForDirectories:(BOOL)flag { _worksForDirectories = flag; }
- (BOOL)worksForFiles { return _worksForFiles; }
- (void)setWorksForFiles:(BOOL)flag { _worksForFiles = flag; }
- (BOOL)recurseIntoSubdirectories { return _recurseIntoSubdirectories; }
- (void)setRecurseIntoSubdirectories:(BOOL)flag { _recurseIntoSubdirectories = flag; }
- (BOOL)askForConfirmation { return _askForConfirmation; }
- (void)setAskForConfirmation:(BOOL)flag { _askForConfirmation = flag; }
- (BOOL)showInTerminal { return _showInTerminal; }
- (void)setShowInTerminal:(BOOL)flag { _showInTerminal = flag; }
- (BOOL)waitForCompletion { return _waitForCompletion; }
- (void)setWaitForCompletion:(BOOL)flag { _waitForCompletion = flag; }
- (LDRefreshPolicy)refreshPolicy { return _refreshPolicy; }
- (void)setRefreshPolicy:(LDRefreshPolicy)policy { _refreshPolicy = policy; }

- (void)normalize
{
  if (!_worksForMountPoints && !_worksForDirectories) {
    _recurseIntoSubdirectories = NO;
  }
  if (_recurseIntoSubdirectories) {
    _waitForCompletion = YES;
  }
  if (!_waitForCompletion) {
    _refreshPolicy = LDRefreshPolicyNone;
  }
}

@end

@implementation LDPreferences

+ (LDPreferences *)sharedPreferences
{
  static LDPreferences *shared = nil;
  if (!shared) {
    shared = [[LDPreferences alloc] initWithUserDefaults:[NSUserDefaults standardUserDefaults]];
  }
  return shared;
}

+ (NSDictionary *)defaultValues
{
  NSMutableDictionary *values = [NSMutableDictionary dictionaryWithDictionary:[self scalarDefaultValues]];
  for (NSUInteger i = 0; i < LDFileTreeColorSlots; i++) {
    [values setObject:@(LDDefaultFileTreeColors[i]) forKey:[self keyForFileTreeColor:i]];
  }
  return values;
}

+ (NSString *)keyForFileTreeColor:(NSUInteger)index
{
  return [NSString stringWithFormat:@"FileTreeColor%lu", (unsigned long)index];
}

+ (NSDictionary *)scalarDefaultValues
{
  return @{
    @"HumanFormat": @YES,
    @"ListGrid": @NO,
    @"ListStripes": @NO,
    @"ListFullRowSelection": @YES,
    @"AutomaticallyResizeColumns": @YES,
    @"FileTreeColorCount": @8,
    @"PacmanAnimation": @YES,
    @"ShowTimeSpent": @YES,
    // WinDirStat shows Physical and Logical Size; at GNOME's metrics only
    // one size column fits beside the extension list, so Logical is off.
    @"ShowColumnSizePhysical": @YES,
    @"ShowColumnSizeLogical": @NO,
    @"ShowColumnItems": @NO,
    @"ShowColumnFiles": @YES,
    @"ShowColumnFolders": @NO,
    @"ShowColumnLastChange": @YES,
    @"ShowColumnAttributes": @NO,
    @"ShowColumnOwner": @NO,
    @"TreeMapStyle": @0,
    @"TreeMapGrid": @NO,
    @"TreeMapBrightness": @88,
    @"TreeMapAmbientLightPercent": @13,
    @"TreeMapHeightFactor": @38,
    @"TreeMapScaleFactor": @91,
    @"TreeMapLightSourceX": @(-100),
    @"TreeMapLightSourceY": @(-100),
    @"TreeMapGridColor": @0x000000,
    @"TreeMapHighlightColor": @0xffffff,
    @"UseLogicalSize": @NO,
    @"FilteringExcludeDirs": @"",
    @"FilteringExcludeFiles": @"",
    @"FilteringUseRegex": @NO,
    @"FilteringSizeMinimum": @0,
    @"FilteringSizeUnits": @0,
    @"ExcludeVolumeMountPoints": @YES,
    @"ExcludeSymbolicLinks": @YES,
    @"ExcludeHidden": @NO,
    @"ProcessHardlinks": @YES,
    @"ScanningThreads": @4,
    @"LargeFileCount": @50,
    @"FolderHistoryCount": @10,
    @"SearchMaxResults": @10000,
    @"ScanForDuplicates": @NO,
    @"ShowDeleteWarning": @YES,
    @"SearchRegex": @NO,
    @"SearchCase": @NO,
    @"SearchWholePhrase": @NO,
    @"SearchTerm": @"",
    @"SelectDrivesRadio": @(LDSelectTargetFolder),
    @"SelectDrivesDrives": @[],
    @"SelectDrivesFolder": @[],
    @"UserDefinedCleanups": @[],
    @"ConfigPage": @0,
    @"ShowFileTypes": @YES,
    @"ShowTreemap": @YES,
    @"ShowToolBar": @YES,
    @"ShowStatusBar": @YES,
    @"LargeToolBar": @NO,
    @"ShowFreeSpace": @NO,
    @"ShowUnknown": @NO,
  };
}

- (id)initWithUserDefaults:(NSUserDefaults *)defaults
{
  self = [super init];
  if (self) {
    _defaults = defaults;
    [_defaults registerDefaults:[LDPreferences defaultValues]];
  }
  return self;
}

- (void)changed
{
  [[NSNotificationCenter defaultCenter] postNotificationName:LDPreferencesDidChangeNotification object:self];
}

- (BOOL)boolForKey:(NSString *)key { return [_defaults boolForKey:key]; }
- (void)setBool:(BOOL)value forKey:(NSString *)key
{
  [_defaults setBool:value forKey:key];
  [self changed];
}
- (NSInteger)integerForKey:(NSString *)key { return [_defaults integerForKey:key]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key
{
  [_defaults setInteger:value forKey:key];
  [self changed];
}
- (NSString *)stringForKey:(NSString *)key { return [_defaults stringForKey:key] ?: @""; }
- (void)setString:(NSString *)value forKey:(NSString *)key
{
  [_defaults setObject:value ?: @"" forKey:key];
  [self changed];
}

static NSInteger LDClamp(NSInteger value, NSInteger low, NSInteger high)
{
  return MAX(low, MIN(high, value));
}

- (void)resetAll
{
  for (NSString *key in [LDPreferences defaultValues]) {
    [_defaults removeObjectForKey:key];
  }
  [self changed];
}

- (BOOL)humanFormat { return [self boolForKey:@"HumanFormat"]; }
- (void)setHumanFormat:(BOOL)flag { [self setBool:flag forKey:@"HumanFormat"]; }
- (BOOL)listGrid { return [self boolForKey:@"ListGrid"]; }
- (void)setListGrid:(BOOL)flag { [self setBool:flag forKey:@"ListGrid"]; }
- (BOOL)listStripes { return [self boolForKey:@"ListStripes"]; }
- (void)setListStripes:(BOOL)flag { [self setBool:flag forKey:@"ListStripes"]; }
- (BOOL)listFullRowSelection { return [self boolForKey:@"ListFullRowSelection"]; }
- (void)setListFullRowSelection:(BOOL)flag { [self setBool:flag forKey:@"ListFullRowSelection"]; }
- (BOOL)automaticallyResizeColumns { return [self boolForKey:@"AutomaticallyResizeColumns"]; }
- (void)setAutomaticallyResizeColumns:(BOOL)flag { [self setBool:flag forKey:@"AutomaticallyResizeColumns"]; }

- (BOOL)pacmanAnimation { return [self boolForKey:@"PacmanAnimation"]; }
- (void)setPacmanAnimation:(BOOL)flag { [self setBool:flag forKey:@"PacmanAnimation"]; }
- (BOOL)showTimeSpent { return [self boolForKey:@"ShowTimeSpent"]; }
- (void)setShowTimeSpent:(BOOL)flag { [self setBool:flag forKey:@"ShowTimeSpent"]; }

+ (NSArray *)optionalColumns
{
  return @[LDColumnPhysicalSize, LDColumnLogicalSize, LDColumnItems, LDColumnFiles,
           LDColumnFolders, LDColumnLastChange, LDColumnAttributes, LDColumnOwner];
}

static uint32_t LDColorValue(NSInteger value)
{
  return (uint32_t)value & 0xffffff;
}

+ (NSUInteger)fileTreeColorSlots { return LDFileTreeColorSlots; }

- (uint32_t)fileTreeColorAtIndex:(NSUInteger)index
{
  if (index >= LDFileTreeColorSlots) {
    return 0;
  }
  return LDColorValue([self integerForKey:[LDPreferences keyForFileTreeColor:index]]);
}

- (void)setFileTreeColor:(uint32_t)color atIndex:(NSUInteger)index
{
  if (index < LDFileTreeColorSlots) {
    [self setInteger:LDColorValue(color) forKey:[LDPreferences keyForFileTreeColor:index]];
  }
}

- (NSUInteger)fileTreeColorCount
{
  return (NSUInteger)LDClamp([self integerForKey:@"FileTreeColorCount"], 1, (NSInteger)LDFileTreeColorSlots);
}

- (void)setFileTreeColorCount:(NSUInteger)count
{
  [self setInteger:LDClamp((NSInteger)count, 1, (NSInteger)LDFileTreeColorSlots) forKey:@"FileTreeColorCount"];
}

- (uint32_t)fileTreeColorForDepth:(NSUInteger)depth
{
  return [self fileTreeColorAtIndex:depth % [self fileTreeColorCount]];
}

+ (NSString *)keyForColumn:(NSString *)column
{
  NSDictionary *keys = @{
    LDColumnPhysicalSize: @"ShowColumnSizePhysical",
    LDColumnLogicalSize: @"ShowColumnSizeLogical",
    LDColumnItems: @"ShowColumnItems",
    LDColumnFiles: @"ShowColumnFiles",
    LDColumnFolders: @"ShowColumnFolders",
    LDColumnLastChange: @"ShowColumnLastChange",
    LDColumnAttributes: @"ShowColumnAttributes",
    LDColumnOwner: @"ShowColumnOwner",
  };
  return [keys objectForKey:column];
}

- (BOOL)isColumnShown:(NSString *)column
{
  NSString *key = [LDPreferences keyForColumn:column];
  return key ? [self boolForKey:key] : YES;
}

- (void)setColumn:(NSString *)column shown:(BOOL)shown
{
  NSString *key = [LDPreferences keyForColumn:column];
  if (key) {
    [self setBool:shown forKey:key];
  }
}

- (NSInteger)treemapStyle { return LDClamp([self integerForKey:@"TreeMapStyle"], 0, 1); }
- (void)setTreemapStyle:(NSInteger)style { [self setInteger:LDClamp(style, 0, 1) forKey:@"TreeMapStyle"]; }
- (BOOL)treemapGrid { return [self boolForKey:@"TreeMapGrid"]; }
- (void)setTreemapGrid:(BOOL)flag { [self setBool:flag forKey:@"TreeMapGrid"]; }
- (NSInteger)treemapBrightness { return LDClamp([self integerForKey:@"TreeMapBrightness"], 0, 100); }
- (void)setTreemapBrightness:(NSInteger)value { [self setInteger:LDClamp(value, 0, 100) forKey:@"TreeMapBrightness"]; }
- (NSInteger)treemapCushionShading { return LDClamp([self integerForKey:@"TreeMapAmbientLightPercent"], 0, 100); }
- (void)setTreemapCushionShading:(NSInteger)value { [self setInteger:LDClamp(value, 0, 100) forKey:@"TreeMapAmbientLightPercent"]; }
- (NSInteger)treemapHeight { return LDClamp([self integerForKey:@"TreeMapHeightFactor"], 0, 100); }
- (void)setTreemapHeight:(NSInteger)value { [self setInteger:LDClamp(value, 0, 100) forKey:@"TreeMapHeightFactor"]; }
- (NSInteger)treemapScaleFactor { return LDClamp([self integerForKey:@"TreeMapScaleFactor"], 0, 100); }
- (void)setTreemapScaleFactor:(NSInteger)value { [self setInteger:LDClamp(value, 0, 100) forKey:@"TreeMapScaleFactor"]; }
- (NSInteger)treemapLightSourceX { return LDClamp([self integerForKey:@"TreeMapLightSourceX"], -100, 100); }
- (void)setTreemapLightSourceX:(NSInteger)value { [self setInteger:LDClamp(value, -100, 100) forKey:@"TreeMapLightSourceX"]; }
- (NSInteger)treemapLightSourceY { return LDClamp([self integerForKey:@"TreeMapLightSourceY"], -100, 100); }
- (void)setTreemapLightSourceY:(NSInteger)value { [self setInteger:LDClamp(value, -100, 100) forKey:@"TreeMapLightSourceY"]; }

- (uint32_t)treemapGridColor { return LDColorValue([self integerForKey:@"TreeMapGridColor"]); }
- (void)setTreemapGridColor:(uint32_t)color { [self setInteger:LDColorValue(color) forKey:@"TreeMapGridColor"]; }
- (uint32_t)treemapHighlightColor { return LDColorValue([self integerForKey:@"TreeMapHighlightColor"]); }
- (void)setTreemapHighlightColor:(uint32_t)color { [self setInteger:LDColorValue(color) forKey:@"TreeMapHighlightColor"]; }

- (LDTreemapOptions)treemapOptions
{
  // Zeroed first, so options compare equal with memcmp.
  LDTreemapOptions options;
  memset(&options, 0, sizeof(options));
  options.style = [self treemapStyle] == 1 ? LDTreemapStyleSequoiaView : LDTreemapStyleKDirStat;
  options.grid = [self treemapGrid];
  options.gridColor = [self treemapGridColor];
  options.brightness = [self treemapBrightness] / 100.0;
  options.ambientLight = [self treemapCushionShading] / 100.0;
  options.height = [self treemapHeight] / 100.0;
  options.scaleFactor = [self treemapScaleFactor] / 100.0;
  options.lightSourceX = [self treemapLightSourceX] / 100.0;
  options.lightSourceY = [self treemapLightSourceY] / 100.0;
  return options;
}

- (void)resetTreemapOptions
{
  for (NSString *key in @[@"TreeMapStyle", @"TreeMapGrid", @"TreeMapBrightness", @"TreeMapAmbientLightPercent",
                          @"TreeMapHeightFactor", @"TreeMapScaleFactor", @"TreeMapLightSourceX", @"TreeMapLightSourceY"]) {
    [_defaults removeObjectForKey:key];
  }
  [self changed];
}

- (BOOL)useLogicalSize { return [self boolForKey:@"UseLogicalSize"]; }
- (void)setUseLogicalSize:(BOOL)flag { [self setBool:flag forKey:@"UseLogicalSize"]; }

- (NSString *)excludedFolderPatterns { return [self stringForKey:@"FilteringExcludeDirs"]; }
- (void)setExcludedFolderPatterns:(NSString *)patterns { [self setString:patterns forKey:@"FilteringExcludeDirs"]; }
- (NSString *)excludedFilePatterns { return [self stringForKey:@"FilteringExcludeFiles"]; }
- (void)setExcludedFilePatterns:(NSString *)patterns { [self setString:patterns forKey:@"FilteringExcludeFiles"]; }
- (BOOL)filterUsesRegex { return [self boolForKey:@"FilteringUseRegex"]; }
- (void)setFilterUsesRegex:(BOOL)flag { [self setBool:flag forKey:@"FilteringUseRegex"]; }

- (unsigned long long)minimumFileSize
{
  return [[_defaults objectForKey:@"FilteringSizeMinimum"] unsignedLongLongValue];
}

- (void)setMinimumFileSize:(unsigned long long)value
{
  [_defaults setObject:[NSNumber numberWithUnsignedLongLong:value] forKey:@"FilteringSizeMinimum"];
  [self changed];
}

- (LDSizeUnit)minimumFileSizeUnit { return (LDSizeUnit)LDClamp([self integerForKey:@"FilteringSizeUnits"], 0, 4); }
- (void)setMinimumFileSizeUnit:(LDSizeUnit)unit { [self setInteger:LDClamp(unit, 0, 4) forKey:@"FilteringSizeUnits"]; }

- (unsigned long long)minimumFileSizeInBytes
{
  return [self minimumFileSize] << (10 * [self minimumFileSizeUnit]);
}

- (BOOL)excludeMountPoints { return [self boolForKey:@"ExcludeVolumeMountPoints"]; }
- (void)setExcludeMountPoints:(BOOL)flag { [self setBool:flag forKey:@"ExcludeVolumeMountPoints"]; }
- (BOOL)excludeSymbolicLinks { return [self boolForKey:@"ExcludeSymbolicLinks"]; }
- (void)setExcludeSymbolicLinks:(BOOL)flag { [self setBool:flag forKey:@"ExcludeSymbolicLinks"]; }
- (BOOL)excludeHiddenEntries { return [self boolForKey:@"ExcludeHidden"]; }
- (void)setExcludeHiddenEntries:(BOOL)flag { [self setBool:flag forKey:@"ExcludeHidden"]; }
- (BOOL)processHardLinks { return [self boolForKey:@"ProcessHardlinks"]; }
- (void)setProcessHardLinks:(BOOL)flag { [self setBool:flag forKey:@"ProcessHardlinks"]; }
- (NSUInteger)scanningThreads { return (NSUInteger)LDClamp([self integerForKey:@"ScanningThreads"], 1, 16); }
- (void)setScanningThreads:(NSUInteger)count { [self setInteger:LDClamp((NSInteger)count, 1, 16) forKey:@"ScanningThreads"]; }
- (NSUInteger)largeFileCount { return (NSUInteger)LDClamp([self integerForKey:@"LargeFileCount"], 0, 10000); }
- (void)setLargeFileCount:(NSUInteger)count { [self setInteger:LDClamp((NSInteger)count, 0, 10000) forKey:@"LargeFileCount"]; }
- (NSUInteger)folderHistoryCount { return (NSUInteger)LDClamp([self integerForKey:@"FolderHistoryCount"], 0, 100); }
- (void)setFolderHistoryCount:(NSUInteger)count
{
  [self setInteger:LDClamp((NSInteger)count, 0, 100) forKey:@"FolderHistoryCount"];
  [self trimFolderHistory];
}
- (NSUInteger)searchMaxResults { return (NSUInteger)MAX((NSInteger)1, [self integerForKey:@"SearchMaxResults"]); }
- (BOOL)scanForDuplicates { return [self boolForKey:@"ScanForDuplicates"]; }
- (void)setScanForDuplicates:(BOOL)flag { [self setBool:flag forKey:@"ScanForDuplicates"]; }

- (BOOL)showDeleteWarning { return [self boolForKey:@"ShowDeleteWarning"]; }
- (void)setShowDeleteWarning:(BOOL)flag { [self setBool:flag forKey:@"ShowDeleteWarning"]; }

- (BOOL)searchUsesRegex { return [self boolForKey:@"SearchRegex"]; }
- (void)setSearchUsesRegex:(BOOL)flag { [self setBool:flag forKey:@"SearchRegex"]; }
- (BOOL)searchCaseSensitive { return [self boolForKey:@"SearchCase"]; }
- (void)setSearchCaseSensitive:(BOOL)flag { [self setBool:flag forKey:@"SearchCase"]; }
- (BOOL)searchWholePhrase { return [self boolForKey:@"SearchWholePhrase"]; }
- (void)setSearchWholePhrase:(BOOL)flag { [self setBool:flag forKey:@"SearchWholePhrase"]; }
- (NSString *)lastSearchTerm { return [self stringForKey:@"SearchTerm"]; }
- (void)setLastSearchTerm:(NSString *)term { [self setString:term forKey:@"SearchTerm"]; }

- (LDSelectTargetMode)selectTargetMode { return (LDSelectTargetMode)LDClamp([self integerForKey:@"SelectDrivesRadio"], 0, 2); }
- (void)setSelectTargetMode:(LDSelectTargetMode)mode { [self setInteger:LDClamp(mode, 0, 2) forKey:@"SelectDrivesRadio"]; }

- (NSArray *)selectedDrives
{
  NSArray *drives = [_defaults arrayForKey:@"SelectDrivesDrives"];
  return drives ?: @[];
}

- (void)setSelectedDrives:(NSArray *)drives
{
  [_defaults setObject:drives ?: @[] forKey:@"SelectDrivesDrives"];
  [self changed];
}

- (NSArray *)folderHistory
{
  NSArray *history = [_defaults arrayForKey:@"SelectDrivesFolder"];
  return history ?: @[];
}

- (void)storeFolderHistory:(NSArray *)history
{
  NSUInteger limit = [self folderHistoryCount];
  if ([history count] > limit) {
    history = [history subarrayWithRange:NSMakeRange(0, limit)];
  }
  [_defaults setObject:history forKey:@"SelectDrivesFolder"];
  [self changed];
}

- (void)trimFolderHistory
{
  [self storeFolderHistory:[self folderHistory]];
}

- (void)addFolderToHistory:(NSString *)folder
{
  if ([folder length] == 0) {
    return;
  }
  NSMutableArray *history = [[self folderHistory] mutableCopy];
  [history removeObject:folder];
  [history insertObject:folder atIndex:0];
  [self storeFolderHistory:history];
}

- (void)removeFolderFromHistory:(NSString *)folder
{
  NSMutableArray *history = [[self folderHistory] mutableCopy];
  [history removeObject:folder];
  [self storeFolderHistory:history];
}

- (NSArray *)customCleanups
{
  NSArray *stored = [_defaults arrayForKey:@"UserDefinedCleanups"];
  NSMutableArray *cleanups = [NSMutableArray arrayWithCapacity:LDCustomCleanupSlots];
  for (NSUInteger i = 0; i < LDCustomCleanupSlots; i++) {
    id entry = i < [stored count] ? [stored objectAtIndex:i] : nil;
    LDCustomCleanup *cleanup = [entry isKindOfClass:[NSDictionary class]]
      ? [[LDCustomCleanup alloc] initWithDictionary:entry]
      : [[LDCustomCleanup alloc] init];
    [cleanups addObject:cleanup];
  }
  return cleanups;
}

- (void)setCustomCleanups:(NSArray *)cleanups
{
  NSMutableArray *stored = [NSMutableArray array];
  for (NSUInteger i = 0; i < LDCustomCleanupSlots; i++) {
    LDCustomCleanup *cleanup = i < [cleanups count] ? [cleanups objectAtIndex:i] : [[LDCustomCleanup alloc] init];
    [cleanup normalize];
    [stored addObject:[cleanup dictionaryRepresentation]];
  }
  [_defaults setObject:stored forKey:@"UserDefinedCleanups"];
  [self changed];
}

- (BOOL)showFileTypes { return [self boolForKey:@"ShowFileTypes"]; }
- (void)setShowFileTypes:(BOOL)flag { [self setBool:flag forKey:@"ShowFileTypes"]; }
- (BOOL)showTreemap { return [self boolForKey:@"ShowTreemap"]; }
- (void)setShowTreemap:(BOOL)flag { [self setBool:flag forKey:@"ShowTreemap"]; }
- (BOOL)showToolBar { return [self boolForKey:@"ShowToolBar"]; }
- (void)setShowToolBar:(BOOL)flag { [self setBool:flag forKey:@"ShowToolBar"]; }
- (BOOL)showStatusBar { return [self boolForKey:@"ShowStatusBar"]; }
- (void)setShowStatusBar:(BOOL)flag { [self setBool:flag forKey:@"ShowStatusBar"]; }
- (BOOL)largeToolBar { return [self boolForKey:@"LargeToolBar"]; }
- (void)setLargeToolBar:(BOOL)flag { [self setBool:flag forKey:@"LargeToolBar"]; }
- (BOOL)showFreeSpace { return [self boolForKey:@"ShowFreeSpace"]; }
- (void)setShowFreeSpace:(BOOL)flag { [self setBool:flag forKey:@"ShowFreeSpace"]; }
- (BOOL)showUnknown { return [self boolForKey:@"ShowUnknown"]; }
- (void)setShowUnknown:(BOOL)flag { [self setBool:flag forKey:@"ShowUnknown"]; }

- (NSInteger)lastOptionsPage { return [self integerForKey:@"ConfigPage"]; }
- (void)setLastOptionsPage:(NSInteger)page { [self setInteger:page forKey:@"ConfigPage"]; }

@end
