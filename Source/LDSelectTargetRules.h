#import <Foundation/Foundation.h>
#import "LDPreferences.h"

@class LDVolume;

// Sort keys for the Select Target drive list (the table column identifiers).
FOUNDATION_EXPORT NSString *const LDSelectTargetColumnName;
FOUNDATION_EXPORT NSString *const LDSelectTargetColumnTotal;
FOUNDATION_EXPORT NSString *const LDSelectTargetColumnFree;
FOUNDATION_EXPORT NSString *const LDSelectTargetColumnUsed;
FOUNDATION_EXPORT NSString *const LDSelectTargetColumnPercent;

// The Select Target dialog's rules (SelectDrivesDlg.cpp), kept apart from
// the panel so they can be tested without a window.
@interface LDSelectTargetRules : NSObject

// "All local drives (/ /home)". Mount points are listed until the list
// would pass about 48 characters, then "…" stands for the rest. With no
// volumes the title is just "All local drives".
+ (NSString *)allLocalDrivesTitleForMountPoints:(NSArray *)mountPoints;

// The folder typed in the combo: "~" expanded, trailing slashes dropped
// ("/" stays). Blank text gives "".
+ (NSString *)folderPathFromText:(NSString *)text;
// YES when the text names an existing directory by an absolute path (after
// "~" expansion).
+ (BOOL)isUsableFolderText:(NSString *)text;

// Whether OK is enabled: All local drives needs at least one volume,
// Individual drives at least one selected row, Folder a usable folder.
+ (BOOL)canConfirmMode:(LDSelectTargetMode)mode
           volumeCount:(NSUInteger)volumeCount
         selectedCount:(NSUInteger)selectedCount
            folderText:(NSString *)folderText;

// The paths to scan: every listed mount point, the selected ones in list
// order, or the folder. nil when the mode cannot be confirmed.
+ (NSArray *)pathsForMode:(LDSelectTargetMode)mode
              mountPoints:(NSArray *)mountPoints
          selectedIndexes:(NSIndexSet *)selectedIndexes
               folderText:(NSString *)folderText;

// "NN.N%" once the volume is queried, else "".
+ (NSString *)percentStringForVolume:(LDVolume *)volume;

// Volumes sorted by a column (nil sorts by name). For the size columns a
// volume not yet queried (or failed) counts as smaller than every queried
// one. Ties go by mount point.
+ (NSArray *)volumes:(NSArray *)volumes sortedByKey:(NSString *)key ascending:(BOOL)ascending;

// Indexes of the volumes whose mount points are in mountPoints.
+ (NSIndexSet *)indexesOfMountPoints:(NSArray *)mountPoints inVolumes:(NSArray *)volumes;

// The folder shown on open: the requested one, else the newest history
// entry, else "".
+ (NSString *)initialFolderForRequested:(NSString *)folder history:(NSArray *)history;

@end
