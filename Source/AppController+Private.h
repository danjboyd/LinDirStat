#import "AppController.h"
#import "LDListViews.h"

@class LDScanSession;

// Shared between AppController's files.
@interface AppController (Private)
- (NSArray *)selectedNodes;
- (BOOL)isScanning;
// Scanning, refreshing or running a file operation.
- (BOOL)isBusy;
- (void)showStatus:(NSString *)status;
- (NSString *)displayPath:(NSString *)path;
- (void)refreshCommandState;
- (void)startBusyIndicator;
// Stops the busy indicator once nothing is running any more.
- (void)finishBusyWork;
// The tree was edited: rebuild the extension list and treemap.
- (void)didChangeTree;
// node was replaced (or removed when replacement is nil).
- (void)forgetNode:(LDFileNode *)node replacement:(LDFileNode *)replacement;
- (void)configureScanSession:(LDScanSession *)session;
- (void)rescan:(id)sender;
- (NSString *)selectedDirectoryPathFromOpenPanel:(NSOpenPanel *)panel;
- (NSTableColumn *)addColumn:(NSString *)identifier
                       title:(NSString *)title
                       width:(CGFloat)width
                       right:(BOOL)rightAligned
                     toTable:(NSTableView *)table;
- (void)setSortPrototypeForColumn:(NSTableColumn *)column ascending:(BOOL)ascending;
- (NSScrollView *)scrollViewWithDocumentView:(NSView *)view;
- (NSString *)describeNode:(LDFileNode *)node;
- (void)showSummaryStatus;
- (void)updateSelectionField;
- (void)fitFlexibleColumns;
// Shows a tree that was not scanned (loaded from CSV).
- (void)showLoadedTree:(LDFileNode *)root fromFile:(NSString *)path;
@end

@interface AppController (FileLists)
- (NSView *)buildFileTabs;
- (NSTableView *)activeFileList;
- (BOOL)isFileList:(NSTableView *)table;
- (NSArray *)rowsOfFileList:(NSTableView *)table;
- (NSArray *)selectedNodesInFileList:(NSTableView *)table;
- (void)fileListSelectionDidChange:(NSTableView *)table;
- (id)fileListValueForColumn:(NSString *)identifier item:(id)item;
- (void)fileListSortDescriptorsDidChange:(NSTableView *)table;
- (void)updateLargestFiles;
- (void)fileListsDidChangeTree;
- (void)resetFileListsForScan;
// After _scanSession has started: follows its duplicate collector, if any.
- (void)fileListsDidStartScan;
// Duplicate detection can go on after the scan; Stop stops it too.
- (BOOL)isFindingDuplicates;
- (void)stopDuplicateDetection;
- (void)fileListsDidFinishScan;
- (void)search:(id)sender;
- (void)saveResultsToCSV:(id)sender;
- (void)saveDuplicatesToCSV:(id)sender;
- (void)loadResultsFromCSV:(id)sender;
- (void)loadResultsFromCSVFile:(NSString *)path;
- (void)computeHash:(id)sender;
@end

@class LDSearchOptions;

@interface LDSearchPanel : NSObject
{
  NSTextField *_termField;
  NSTextField *_errorLabel;
  NSButton *_regexBox;
  NSButton *_caseBox;
  NSButton *_wholeBox;
  NSButton *_okButton;
}
// Returns the options to search with, or nil if cancelled.
+ (LDSearchOptions *)runSearchPanel;
@end

@interface AppController (Cleanup)
- (void)openItem:(id)sender;
- (void)revealItem:(id)sender;
- (void)openTerminal:(id)sender;
- (void)showProperties:(id)sender;
- (void)copyPath:(id)sender;
- (void)moveToTrash:(id)sender;
- (void)deletePermanently:(id)sender;
- (void)deleteNodes:(NSArray *)nodes permanently:(BOOL)permanently;
- (void)emptyFolder:(id)sender;
- (void)moveItemsTo:(id)sender;
- (void)emptyTrash:(id)sender;
- (void)runCustomCleanup:(id)sender;
- (NSMenu *)customCleanupMenu;
- (void)refreshSelected:(id)sender;
- (void)refreshNodes:(NSArray *)nodes;
- (LDFileNode *)nodeForPathData:(NSData *)pathData;
@end
