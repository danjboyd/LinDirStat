#import <Foundation/Foundation.h>
#import "LDFileNode.h"

#include <pthread.h>
#include <sys/types.h>

// WinDirStat's hard-link handling ("Scan drives and display hardlink
// information", Item.Extended.cpp DoHardlinkAdjustment). A file with several
// links in the tree is counted once, under a "<Hardlinks>" pseudo-folder in
// its scan root, and each link shows "⧉ <size>" in the Physical Size column
// while adding nothing to its folders.

// The pseudo-items under "<Hardlinks>": the container, the "Index ≡ 0xNN"
// sets (inode modulo 20, as WinDirStat groups them), one "Index 0x…" folder
// per linked file and, inside it, one reference per link, named by the
// link's path.
typedef enum {
  LDHardLinkItemNone = 0,
  LDHardLinkItemContainer,
  LDHardLinkItemIndexSet,
  LDHardLinkItemIndex,
  LDHardLinkItemReference
} LDHardLinkItemType;

FOUNDATION_EXPORT LDHardLinkItemType LDHardLinkItemTypeOfNode(LDFileNode *node);
// YES for any of the pseudo-items above. They are not files on disk: they are
// left out of the extension list, file lists, CSV and every command.
FOUNDATION_EXPORT BOOL LDIsHardLinkItem(LDFileNode *node);

@class LDHardLinkSet;

// The hard links of one scan: every file with st_nlink > 1, grouped by
// device and inode. A node of the tree is in at most one set. Thread-safe.
// A fresh scan keeps its table alive with its root (see +tableForRoot:);
// Refresh Selected keeps using it, so a refreshed subtree does not count again
// files whose other links are outside it.
@interface LDHardLinkTable : NSObject
{
  pthread_mutex_t _lock;
  NSMutableDictionary *_setsByIdentity;
  NSMapTable *_setsByNode;
  NSMutableArray *_retiredItems;
  BOOL _showsHardLinks;
  BOOL _matchesInodesOnly;
}

// The table a scan or CSV load attached to root, or nil.
+ (LDHardLinkTable *)tableForRoot:(LDFileNode *)root;

// WinDirStat's ProcessHardlinks: YES shows "<Hardlinks>" and the markers.
// Either way a file is counted once.
- (BOOL)showsHardLinks;
- (void)setShowsHardLinks:(BOOL)flag;

// A table read from a CSV has no devices (they are 0); links scanned later
// (Refresh Selected) then match by inode alone.
- (BOOL)matchesInodesOnly;
- (void)setMatchesInodesOnly:(BOOL)flag;

// Records node as a link to the file (device, inode) with the given sizes.
// Returns YES if node's bytes are to be counted: it is the file's first link,
// not counting links below ignored (the subtree a refresh replaces).
// Otherwise the caller zeroes node and marks it LDFileNodeErrorHardLinkDuplicate.
- (BOOL)addLink:(LDFileNode *)node
         device:(dev_t)device
          inode:(unsigned long long)inode
           size:(unsigned long long)size
  allocatedSize:(unsigned long long)allocatedSize
  ignoringLinksUnder:(LDFileNode *)ignored;

// Forgets the links at and below node (a subtree that left the tree). If a
// set loses its counted link, a remaining link takes over the file's bytes;
// those nodes (whose sizes changed) are returned so their folders' totals
// can be updated.
- (NSArray *)removeLinksUnder:(LDFileNode *)node;

- (LDHardLinkSet *)setForNode:(LDFileNode *)node;
// Every set, ordered by inode.
- (NSArray *)sets;
// Keeps pseudo-items replaced in the tree alive (see +[LDHardLinks updateTree:...]).
- (void)retireItems:(NSArray *)items;

@end

@interface LDHardLinkSet : NSObject
{
  dev_t _device;
  unsigned long long _inode;
  unsigned long long _size;
  unsigned long long _allocatedSize;
  NSMutableArray *_members;
}

- (dev_t)device;
// WinDirStat's Index (the file ID; the inode here).
- (unsigned long long)inode;
// The file's logical and physical size, each link's own.
- (unsigned long long)size;
- (unsigned long long)allocatedSize;
// The links found, in the order they were found.
- (NSArray *)members;

@end

@interface LDHardLinks : NSObject

// Brings the tree below root (a scan root or "This Computer") in line with
// table: links of files with two or more links in the tree are marked
// (-[LDFileNode isHardLink]) when the table shows hard links and unmarked
// otherwise, and each scan root's "<Hardlinks>" folder is rebuilt, or removed
// when it would be empty. The rebuilt folders are totalled and sorted by
// metric; arrays replaced in a live tree are added to retired.
//
// Returns the folders whose totals are now out of date (those of links that
// were marked or unmarked, and the scan roots whose "<Hardlinks>" changed),
// for -updateTotalsUpwardSortedByMetric: when editing a finished tree. After
// a scan, a full recalculation does the same. Replaced pseudo-items are kept
// alive by the table, as views may still hold them.
+ (NSArray *)updateTree:(LDFileNode *)root
                  table:(LDHardLinkTable *)table
                 metric:(LDSizeMetric)metric
               retiring:(NSMutableArray *)retired;

// The "<Hardlinks>" folder of root's scan root, or nil.
+ (LDFileNode *)containerForNode:(LDFileNode *)node;
// The Index folder of a marked link's file, or nil.
+ (LDFileNode *)indexNodeForLink:(LDFileNode *)node;
// The link a reference stands for, or nil if node is not a reference.
+ (LDFileNode *)linkForReference:(LDFileNode *)node;
// The set an Index folder or reference belongs to, or nil.
+ (LDHardLinkSet *)setForItem:(LDFileNode *)node;

// WinDirStat's treemap colour for the pseudo-items: RGB(200, 150, 100),
// drawn lighter (COLORFLAG_LIGHTER).
+ (uint32_t)treemapColor;

@end
