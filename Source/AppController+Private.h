#import "AppController.h"
#import "LDListViews.h"

@class LDScanSession;
@class LDSearchOptions;

// Shared between AppController's files.
@interface AppController (Private)
- (NSArray *)selectedNodes;
- (NSString *)statusForSelection:(NSArray *)nodes;
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
// Brings <Free Space> and <Unknown> in line with the Options menu, with
// fresh sizes. Call before -didChangeTree after a scan or refresh. Returns
// NO when the tree is certainly unchanged.
- (BOOL)updateSpaceItems;
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
- (void)revealNodeInTree:(LDFileNode *)node;
- (void)showSummaryStatus;
- (void)updateSelectionField;
- (void)fitFlexibleColumns;
// Shows a tree that was not scanned (loaded from CSV).
- (void)showLoadedTree:(LDFileNode *)root fromFile:(NSString *)path;
@end

// The file lists are tables whose data source and delegate are the controller.
@interface AppController (FileLists) <NSTableViewDataSource, NSTableViewDelegate>
- (NSView *)buildFileTabs;
- (NSTableView *)activeFileList;
- (BOOL)isFileList:(NSTableView *)table;
- (NSArray *)rowsOfFileList:(NSTableView *)table;
- (NSArray *)selectedNodesInFileList:(NSTableView *)table;
- (void)fileListSelectionDidChange:(NSTableView *)table;
- (id)fileListValueForColumn:(NSString *)identifier item:(id)item;
- (void)fileListSortDescriptorsDidChange:(NSTableView *)table;
- (void)updateLargestFiles;
- (void)showLargestFiles:(NSArray *)files;
- (void)fileListsDidChangeTree;
- (void)resetFileListsForScan;
// After _scanSession has started: follows its duplicate collector, if any.
- (void)fileListsDidStartScan;
// Duplicate detection can go on after the scan; Stop stops it too.
- (BOOL)isFindingDuplicates;
- (void)stopDuplicateDetection;
// largestFiles, if not nil, are the Largest Files worked out with the scan.
- (void)fileListsDidFinishScanWithLargestFiles:(NSArray *)largestFiles;
- (void)search:(id)sender;
// Search's results tab for options (the Search dialog's answer).
- (void)showSearchResultsForOptions:(LDSearchOptions *)options;
- (void)saveResultsToCSV:(id)sender;
- (void)saveDuplicatesToCSV:(id)sender;
- (void)loadResultsFromCSV:(id)sender;
- (void)loadResultsFromCSVFile:(NSString *)path;
- (void)computeHash:(id)sender;
// Tools › Start/Stop File Watcher.
- (void)toggleFileWatcher:(id)sender;
- (BOOL)isFileWatcherOn;
@end

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

// LINDIRSTAT_DUMP_LAYOUT: geometry for the full-window GUI parity gate.
@interface AppController (LayoutDump)
- (void)startLayoutDumpIfRequested;
@end

@class LDHardLinkTable;

@interface AppController (HardLinks)
- (LDHardLinkTable *)hardLinkTable;
- (NSString *)physicalSizeStringForNode:(LDFileNode *)node;
- (NSString *)logicalSizeStringForNode:(LDFileNode *)node;
- (BOOL)listView:(NSTableView *)view hasLinkAtRow:(NSInteger)row column:(NSInteger)column;
- (void)listView:(NSTableView *)view followLinkAtRow:(NSInteger)row column:(NSInteger)column;
- (void)prepareRefreshSession:(LDScanSession *)session ofNode:(LDFileNode *)node;
- (void)updateHardLinksAfterReplacing:(LDFileNode *)node withNode:(LDFileNode *)replacement canceled:(BOOL)canceled;
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
- (void)excludeItem:(id)sender;
- (void)removeEmptyFolders:(id)sender;
- (void)setFolderDates:(id)sender;
- (void)deduplicateWithHardLinks:(id)sender;
- (NSArray *)hardLinkPairs;
- (void)excludeExtension:(id)sender;
- (NSString *)exclusionPatternForSelectedExtension;
- (LDFileNode *)nodeForPathData:(NSData *)pathData;
// The Open With submenu: the applications for nodes, or none.
- (void)fillOpenWithMenu:(NSMenu *)menu forNodes:(NSArray *)nodes;
- (void)openWithApplication:(id)sender;
@end
