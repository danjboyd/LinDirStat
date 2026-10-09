#import <AppKit/AppKit.h>
#import "LDFileNode.h"
#import "LDTreeSorting.h"
#import "LDListViews.h"

@class LDScanSession;
@class LDTreemapView;

@interface AppController : NSObject <NSApplicationDelegate>
{
  NSWindow *_window;
  NSSplitView *_mainSplit;
  NSSplitView *_topSplit;
  LDOutlineView *_directoryTable;
  NSTableView *_extensionTable;
  LDTreemapView *_treemapView;
  NSTextField *_statusField;
  NSTextField *_selectionField;
  NSTextField *_memoryField;
  NSProgressIndicator *_spinner;
  NSArray *_extensionRows;
  NSMutableDictionary *_swatchCache;
  NSMutableDictionary *_tintedIcons;
  NSMapTable *_sortedChildrenCache;
  LDScanSession *_scanSession;
  NSTimer *_memoryTimer;
  LDFileNode *_rootNode;
  NSString *_currentScanPath;
  NSDateFormatter *_dateFormatter;
  LDSizeMetric _sizeMetric;
  LDTreeSortKey _treeSortKey;
  BOOL _treeSortAscending;
  BOOL _treeSortIsDefault;
  BOOL _syncingSelection;
  BOOL _splitPositionsSet;
  NSTimeInterval _lastLiveReload;
  NSTimeInterval _pacmanEpoch;
  NSTimer *_busyTimer;
  NSMutableArray *_refreshQueue;
  LDScanSession *_refreshSession;
  BOOL _fileOperationRunning;
  NSMenu *_cleanupMenu;
  NSMutableDictionary *_optionalColumns;
  NSMapTable *_ownerCache;
}
@end
