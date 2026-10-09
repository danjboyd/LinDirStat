#import "LDSelectTargetRules.h"
#import "LDVolumes.h"

NSString *const LDSelectTargetColumnName = @"name";
NSString *const LDSelectTargetColumnTotal = @"total";
NSString *const LDSelectTargetColumnFree = @"free";
NSString *const LDSelectTargetColumnUsed = @"used";
NSString *const LDSelectTargetColumnPercent = @"percent";

static const NSUInteger LDAllDrivesListLength = 48;

@implementation LDSelectTargetRules

+ (NSString *)allLocalDrivesTitleForMountPoints:(NSArray *)mountPoints
{
  NSString *title = @"All local drives";
  if ([mountPoints count] == 0) {
    return title;
  }
  NSMutableString *list = [NSMutableString string];
  for (NSString *mountPoint in mountPoints) {
    if ([list length] > 0 && [list length] + 1 + [mountPoint length] > LDAllDrivesListLength) {
      [list appendString:@" …"];
      break;
    }
    if ([list length] > 0) {
      [list appendString:@" "];
    }
    [list appendString:mountPoint];
  }
  return [NSString stringWithFormat:@"%@ (%@)", title, list];
}

+ (NSString *)folderPathFromText:(NSString *)text
{
  if ([[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
    return @"";
  }
  NSString *path = [text stringByExpandingTildeInPath];
  while ([path length] > 1 && [path hasSuffix:@"/"]) {
    path = [path substringToIndex:[path length] - 1];
  }
  return path;
}

+ (BOOL)isUsableFolderText:(NSString *)text
{
  NSString *path = [self folderPathFromText:text];
  if (![path isAbsolutePath]) {
    return NO;
  }
  BOOL isDirectory = NO;
  return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory;
}

+ (BOOL)canConfirmMode:(LDSelectTargetMode)mode
           volumeCount:(NSUInteger)volumeCount
         selectedCount:(NSUInteger)selectedCount
            folderText:(NSString *)folderText
{
  switch (mode) {
    case LDSelectTargetAllLocalDrives: return volumeCount > 0;
    case LDSelectTargetIndividualDrives: return selectedCount > 0;
    case LDSelectTargetFolder: return [self isUsableFolderText:folderText];
  }
  return NO;
}

+ (NSArray *)pathsForMode:(LDSelectTargetMode)mode
              mountPoints:(NSArray *)mountPoints
          selectedIndexes:(NSIndexSet *)selectedIndexes
               folderText:(NSString *)folderText
{
  NSMutableIndexSet *selected = [NSMutableIndexSet indexSet];
  [selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
    (void)stop;
    if (index < [mountPoints count]) {
      [selected addIndex:index];
    }
  }];
  if (![self canConfirmMode:mode volumeCount:[mountPoints count] selectedCount:[selected count] folderText:folderText]) {
    return nil;
  }
  switch (mode) {
    case LDSelectTargetAllLocalDrives: return [mountPoints copy];
    case LDSelectTargetIndividualDrives: return [mountPoints objectsAtIndexes:selected];
    case LDSelectTargetFolder: return @[[self folderPathFromText:folderText]];
  }
  return nil;
}

+ (NSString *)percentStringForVolume:(LDVolume *)volume
{
  if (![volume isQueried]) {
    return @"";
  }
  return [NSString stringWithFormat:@"%.1f%%", [volume usedFraction] * 100.0];
}

// A column's sort value; -1 until the volume is queried.
+ (double)sortValueOfVolume:(LDVolume *)volume key:(NSString *)key
{
  if (![volume isQueried]) {
    return -1.0;
  }
  if ([key isEqualToString:LDSelectTargetColumnTotal]) {
    return (double)[volume totalBytes];
  }
  if ([key isEqualToString:LDSelectTargetColumnFree]) {
    return (double)[volume freeBytes];
  }
  return [volume usedFraction];
}

+ (NSArray *)volumes:(NSArray *)volumes sortedByKey:(NSString *)key ascending:(BOOL)ascending
{
  BOOL byName = key == nil || [key isEqualToString:LDSelectTargetColumnName];
  return [volumes sortedArrayUsingComparator:^NSComparisonResult(LDVolume *left, LDVolume *right) {
    NSComparisonResult result = NSOrderedSame;
    if (byName) {
      result = [[left displayName] caseInsensitiveCompare:[right displayName]];
    } else {
      double a = [self sortValueOfVolume:left key:key];
      double b = [self sortValueOfVolume:right key:key];
      result = a < b ? NSOrderedAscending : (a > b ? NSOrderedDescending : NSOrderedSame);
    }
    if (!ascending) {
      result = (NSComparisonResult)-result;
    }
    return result != NSOrderedSame ? result : [[left mountPoint] compare:[right mountPoint]];
  }];
}

+ (NSIndexSet *)indexesOfMountPoints:(NSArray *)mountPoints inVolumes:(NSArray *)volumes
{
  NSSet *wanted = [NSSet setWithArray:mountPoints ?: @[]];
  NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
  [volumes enumerateObjectsUsingBlock:^(LDVolume *volume, NSUInteger index, BOOL *stop) {
    (void)stop;
    if ([wanted containsObject:[volume mountPoint]]) {
      [indexes addIndex:index];
    }
  }];
  return indexes;
}

+ (NSString *)initialFolderForRequested:(NSString *)folder history:(NSArray *)history
{
  if ([folder length] > 0) {
    return folder;
  }
  NSString *newest = [history count] > 0 ? [history objectAtIndex:0] : nil;
  return [newest isKindOfClass:[NSString class]] ? newest : @"";
}

@end
