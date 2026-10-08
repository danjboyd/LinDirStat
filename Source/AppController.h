#import <AppKit/AppKit.h>
#import "LDFileNode.h"

@class LDScanSession;
@class LDTreemapView;

@interface AppController : NSObject <NSApplicationDelegate>
{
  NSWindow *_window;
  NSTextField *_titleField;
  NSButton *_openButton;
  NSButton *_rescanButton;
  NSButton *_stopButton;
  NSTextField *_directoryLabel;
  NSTextField *_extensionLabel;
  NSTextField *_treemapLabel;
  NSScrollView *_directoryScroll;
  NSScrollView *_extensionScroll;
  NSOutlineView *_directoryTable;
  NSTableView *_extensionTable;
  NSTextField *_statusField;
  NSTextField *_pathField;
  LDTreemapView *_treemapView;
  NSArray *_extensionRows;
  NSMutableDictionary *_swatchCache;
  LDScanSession *_scanSession;
  NSTimer *_scanTimer;
  LDFileNode *_rootNode;
  NSString *_currentScanPath;
  NSDateFormatter *_dateFormatter;
  LDSizeMetric _sizeMetric;
  BOOL _syncingSelection;
}
@end
