#import <Foundation/Foundation.h>
#import "LDTreemapLayout.h"

// User settings, stored in NSUserDefaults under WinDirStat's setting names
// (Options.cpp). Defaults follow WinDirStat unless noted. Changes post
// LDPreferencesDidChangeNotification.
FOUNDATION_EXPORT NSString *const LDPreferencesDidChangeNotification;

// Optional directory tree columns, in WinDirStat's fixed order.
FOUNDATION_EXPORT NSString *const LDColumnPhysicalSize;
FOUNDATION_EXPORT NSString *const LDColumnLogicalSize;
FOUNDATION_EXPORT NSString *const LDColumnItems;
FOUNDATION_EXPORT NSString *const LDColumnFiles;
FOUNDATION_EXPORT NSString *const LDColumnFolders;
FOUNDATION_EXPORT NSString *const LDColumnLastChange;
FOUNDATION_EXPORT NSString *const LDColumnAttributes;
FOUNDATION_EXPORT NSString *const LDColumnOwner;

typedef enum {
  LDSelectTargetAllLocalDrives = 0,
  LDSelectTargetIndividualDrives = 1,
  LDSelectTargetFolder = 2
} LDSelectTargetMode;

typedef enum {
  LDRefreshPolicyNone = 0,
  LDRefreshPolicyEntry = 1,
  LDRefreshPolicyParent = 2
} LDRefreshPolicy;

typedef enum {
  LDSizeUnitBytes = 0,
  LDSizeUnitKiB = 1,
  LDSizeUnitMiB = 2,
  LDSizeUnitGiB = 3,
  LDSizeUnitTiB = 4
} LDSizeUnit;

// One "Custom Cleanup" slot (Options.h USERDEFINEDCLEANUP). Slot i has the
// shortcut Ctrl+i. Commands run with /bin/sh -c; %p is the item's path, %n
// its name, %sp/%sn the current subfolder in recursive mode. Paths are not
// quoted automatically, as in WinDirStat.
@interface LDCustomCleanup : NSObject <NSCopying>
{
  NSString *_title;
  NSString *_commandLine;
  BOOL _enabled;
  BOOL _worksForMountPoints;
  BOOL _worksForDirectories;
  BOOL _worksForFiles;
  BOOL _recurseIntoSubdirectories;
  BOOL _askForConfirmation;
  BOOL _showInTerminal;
  BOOL _waitForCompletion;
  LDRefreshPolicy _refreshPolicy;
}

+ (NSString *)defaultTitleForSlot:(NSUInteger)slot;
- (NSDictionary *)dictionaryRepresentation;
- (id)initWithDictionary:(NSDictionary *)dictionary;

// The title, or "Custom Cleanup #i" while it is empty.
- (NSString *)displayTitleForSlot:(NSUInteger)slot;

- (NSString *)title;
- (void)setTitle:(NSString *)title;
- (NSString *)commandLine;
- (void)setCommandLine:(NSString *)commandLine;
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)enabled;
// "Drives" in WinDirStat: scan roots and mount points.
- (BOOL)worksForMountPoints;
- (void)setWorksForMountPoints:(BOOL)flag;
- (BOOL)worksForDirectories;
- (void)setWorksForDirectories:(BOOL)flag;
- (BOOL)worksForFiles;
- (void)setWorksForFiles:(BOOL)flag;
- (BOOL)recurseIntoSubdirectories;
- (void)setRecurseIntoSubdirectories:(BOOL)flag;
- (BOOL)askForConfirmation;
- (void)setAskForConfirmation:(BOOL)flag;
// "Show Console Window" in WinDirStat.
- (BOOL)showInTerminal;
- (void)setShowInTerminal:(BOOL)flag;
- (BOOL)waitForCompletion;
- (void)setWaitForCompletion:(BOOL)flag;
- (LDRefreshPolicy)refreshPolicy;
- (void)setRefreshPolicy:(LDRefreshPolicy)policy;

// Applies the Cleanups page rules (PageCleanups.cpp): recursion needs mount
// points or folders and forces waiting; without waiting there is no refresh.
- (void)normalize;

@end

typedef enum {
  LDPromptDeletePermanently = 0,  // Delete Permanently, Empty Folder
  LDPromptMoveToTrash,
  LDPromptEmptyTrash,
  LDPromptCreateHardLink,
  LDPromptSetFolderDates,
  LDPromptRemoveEmptyFolders
} LDPrompt;

@interface LDPreferences : NSObject
{
  NSUserDefaults *_defaults;
}

+ (LDPreferences *)sharedPreferences;
// For tests: preferences backed by a private defaults domain.
- (id)initWithUserDefaults:(NSUserDefaults *)defaults;
+ (NSDictionary *)defaultValues;
// Removes every stored setting ("Reset All Preferences").
- (void)resetAll;

// General
// Sizes as "1.2 GB" (YES) or "1,234,567 bytes" (NO).
- (BOOL)humanFormat;
- (void)setHumanFormat:(BOOL)flag;
- (BOOL)listGrid;
- (void)setListGrid:(BOOL)flag;
- (BOOL)listStripes;
- (void)setListStripes:(BOOL)flag;
- (BOOL)listFullRowSelection;
- (void)setListFullRowSelection:(BOOL)flag;
// Size the list columns to their contents after a scan (default YES).
- (BOOL)automaticallyResizeColumns;
- (void)setAutomaticallyResizeColumns:(BOOL)flag;

// Folder List
- (BOOL)pacmanAnimation;
- (void)setPacmanAnimation:(BOOL)flag;
- (BOOL)showTimeSpent;
- (void)setShowTimeSpent:(BOOL)flag;
- (BOOL)isColumnShown:(NSString *)column;
- (void)setColumn:(NSString *)column shown:(BOOL)shown;
+ (NSArray *)optionalColumns;
// The Subtree Percentage bar colours by depth (WinDirStat's FileTreeColor0-7)
// and how many of them are used in turn (FileTreeColorCount, 1-8). Colours
// are 0xRRGGBB; the defaults are GNOME's palette in WinDirStat's order.
+ (NSUInteger)fileTreeColorSlots;
- (uint32_t)fileTreeColorAtIndex:(NSUInteger)index;
- (void)setFileTreeColor:(uint32_t)color atIndex:(NSUInteger)index;
- (NSUInteger)fileTreeColorCount;
- (void)setFileTreeColorCount:(NSUInteger)count;
// The colour of a bar at depth: colour depth % count.
- (uint32_t)fileTreeColorForDepth:(NSUInteger)depth;

// Treemap. Stored as the WinDirStat percentages.
- (NSInteger)treemapStyle;               // 0 KDirStat, 1 SequoiaView
- (void)setTreemapStyle:(NSInteger)style;
- (BOOL)treemapGrid;
- (void)setTreemapGrid:(BOOL)flag;
- (NSInteger)treemapBrightness;          // 88
- (void)setTreemapBrightness:(NSInteger)value;
- (NSInteger)treemapCushionShading;      // 13
- (void)setTreemapCushionShading:(NSInteger)value;
- (NSInteger)treemapHeight;              // 38
- (void)setTreemapHeight:(NSInteger)value;
- (NSInteger)treemapScaleFactor;         // 91
- (void)setTreemapScaleFactor:(NSInteger)value;
- (NSInteger)treemapLightSourceX;        // -100..100, default -100
- (void)setTreemapLightSourceX:(NSInteger)value;
- (NSInteger)treemapLightSourceY;        // -100..100, default -100
- (void)setTreemapLightSourceY:(NSInteger)value;
// Grid and selection frame colours, 0xRRGGBB (black and white).
- (uint32_t)treemapGridColor;
- (void)setTreemapGridColor:(uint32_t)color;
- (uint32_t)treemapHighlightColor;
- (void)setTreemapHighlightColor:(uint32_t)color;
// Every treemap setting above, as LDTreemap takes them.
- (LDTreemapOptions)treemapOptions;
// Style, grid and cushion settings; the colours are kept, as WinDirStat's
// Reset keeps them.
- (void)resetTreemapOptions;
- (BOOL)useLogicalSize;
- (void)setUseLogicalSize:(BOOL)flag;
// WinDirStat 2.6's UseAbsolutePercentages (default on): the Percentage
// column shows each row's share of the whole scan, not of its parent.
- (BOOL)useAbsolutePercentages;
- (void)setUseAbsolutePercentages:(BOOL)flag;

// Filtering (PageFiltering). Patterns are one per line.
- (NSString *)excludedFolderPatterns;
- (void)setExcludedFolderPatterns:(NSString *)patterns;
- (NSString *)excludedFilePatterns;
- (void)setExcludedFilePatterns:(NSString *)patterns;
- (BOOL)filterUsesRegex;
- (void)setFilterUsesRegex:(BOOL)flag;
- (unsigned long long)minimumFileSize;   // value in the unit below
- (void)setMinimumFileSize:(unsigned long long)value;
- (LDSizeUnit)minimumFileSizeUnit;
- (void)setMinimumFileSizeUnit:(LDSizeUnit)unit;
- (unsigned long long)minimumFileSizeInBytes;
// WinDirStat 2.6: include patterns, "<"/">" for the size and age filters,
// and the age filter (days, 0 = off).
- (NSString *)includedFolderPatterns;
- (void)setIncludedFolderPatterns:(NSString *)patterns;
- (NSString *)includedFilePatterns;
- (void)setIncludedFilePatterns:(NSString *)patterns;
- (BOOL)filterExcludesLargerFiles;        // FilteringSizeComparison: NO "<" (default), YES ">"
- (void)setFilterExcludesLargerFiles:(BOOL)flag;
- (NSUInteger)filterMaximumAgeDays;       // 0..36500
- (void)setFilterMaximumAgeDays:(NSUInteger)days;
- (BOOL)filterExcludesNewerFiles;         // FilteringMaxAgeComparison: NO ">" older (default), YES "<" newer
- (void)setFilterExcludesNewerFiles:(BOOL)flag;

// Advanced: scan exclusions and limits.
- (BOOL)excludeMountPoints;              // YES: do not enter other filesystems
- (void)setExcludeMountPoints:(BOOL)flag;
- (BOOL)excludeSymbolicLinks;            // YES: file links skipped, folder links shown as leaves
- (void)setExcludeSymbolicLinks:(BOOL)flag;
- (BOOL)excludeHiddenEntries;            // dot-names; default NO
- (void)setExcludeHiddenEntries:(BOOL)flag;
- (BOOL)processHardLinks;                // "<Hardlinks>" and ⧉ markers; default YES
- (void)setProcessHardLinks:(BOOL)flag;
- (NSUInteger)scanningThreads;           // 1..16, default 4
- (void)setScanningThreads:(NSUInteger)count;
- (NSUInteger)largeFileCount;            // 0..10000, default 50
- (void)setLargeFileCount:(NSUInteger)count;
- (NSUInteger)folderHistoryCount;        // 0..100, default 10
- (void)setFolderHistoryCount:(NSUInteger)count;
- (NSUInteger)searchMaxResults;          // default 10000
- (BOOL)scanForDuplicates;               // default NO
- (void)setScanForDuplicates:(BOOL)flag;

// Prompts (WinDirStat 2.6's per-operation confirmations, 581c609d): one
// "Show confirmation before" switch per destructive operation, each on by
// default. "Don't ask again" in a confirmation turns off only its own.
+ (NSArray *)prompts;                    // LDPrompt values, as NSNumbers, in page order
- (BOOL)showsPrompt:(LDPrompt)prompt;
- (void)setShowsPrompt:(BOOL)flag forPrompt:(LDPrompt)prompt;

// Search dialog
- (BOOL)searchUsesRegex;
- (void)setSearchUsesRegex:(BOOL)flag;
- (BOOL)searchCaseSensitive;
- (void)setSearchCaseSensitive:(BOOL)flag;
- (BOOL)searchWholePhrase;
- (void)setSearchWholePhrase:(BOOL)flag;
- (NSString *)lastSearchTerm;
- (void)setLastSearchTerm:(NSString *)term;
// WinDirStat 2.6-2.7's search settings, under its keys: item types, owner,
// the size range fields as typed (digits, empty for no bound) with their
// unit (0 bytes .. 4 TiB, default MiB), and the history: dictionaries with
// Term, Regex, WholePhrase and Case, newest first.
- (BOOL)searchIncludesFiles;
- (void)setSearchIncludesFiles:(BOOL)flag;
- (BOOL)searchIncludesFolders;
- (void)setSearchIncludesFolders:(BOOL)flag;
- (NSString *)searchOwner;
- (void)setSearchOwner:(NSString *)owner;
- (NSString *)searchSizeField:(NSString *)key;   // SearchSizeMinimum, SearchSizeMaximum, SearchPhysicalMinimum, SearchPhysicalMaximum
- (void)setSearchSizeField:(NSString *)value forKey:(NSString *)key;
- (NSInteger)searchSizeUnits;
- (void)setSearchSizeUnits:(NSInteger)unit;
- (NSInteger)searchPhysicalUnits;
- (void)setSearchPhysicalUnits:(NSInteger)unit;
- (NSArray *)searchHistory;
- (void)setSearchHistory:(NSArray *)history;
- (NSUInteger)searchHistoryCount;        // 0..100, default 10

// Select Target dialog
- (LDSelectTargetMode)selectTargetMode;
- (void)setSelectTargetMode:(LDSelectTargetMode)mode;
- (NSArray *)selectedDrives;             // mount point paths
- (void)setSelectedDrives:(NSArray *)drives;
- (NSArray *)folderHistory;              // most recent first
- (void)addFolderToHistory:(NSString *)folder;
- (void)removeFolderFromHistory:(NSString *)folder;

// Custom cleanups: always 10 slots.
- (NSArray *)customCleanups;
- (void)setCustomCleanups:(NSArray *)cleanups;

// Options menu: the extension list and the treemap panes.
- (BOOL)showFileTypes;
- (void)setShowFileTypes:(BOOL)flag;
- (BOOL)showTreemap;
- (void)setShowTreemap:(BOOL)flag;
// Options menu: toolbar, status bar and large toolbar icons.
- (BOOL)showToolBar;
- (void)setShowToolBar:(BOOL)flag;
- (BOOL)showStatusBar;
- (void)setShowStatusBar:(BOOL)flag;
- (BOOL)largeToolBar;
- (void)setLargeToolBar:(BOOL)flag;
// Options menu: <Free Space> and <Unknown> under volume roots (off by default).
- (BOOL)showFreeSpace;
- (void)setShowFreeSpace:(BOOL)flag;
- (BOOL)showUnknown;
- (void)setShowUnknown:(BOOL)flag;

// Options dialog page last shown.
- (NSInteger)lastOptionsPage;
- (void)setLastOptionsPage:(NSInteger)page;

@end
