#import <Foundation/Foundation.h>

// Destructive filesystem operations. Paths are exact filesystem bytes (see
// -[LDFileNode pathData]); nothing here goes through NSString paths.
//
// Errors are in NSPOSIXErrorDomain with a localized description that names
// the failing step.
@interface LDFileOperations : NSObject

// Moves the item to the trash. On Linux this follows the freedesktop.org
// Trash specification 1.0: the home trash ($XDG_DATA_HOME/Trash) for items on
// its filesystem, otherwise $topdir/.Trash/$uid (when $topdir/.Trash is a
// sticky, non-symlinked directory) or $topdir/.Trash-$uid. Items are never
// copied across filesystems. On macOS NSFileManager's trash is used.
+ (BOOL)moveToTrash:(NSData *)path error:(NSError **)error;

// Deletes the item permanently; directories are removed recursively. Never
// follows symlinks and never enters another filesystem. Like rm -r it keeps
// going past entries it cannot remove (a mount point inside the item fails
// with EXDEV) and reports the first failure; those entries and their
// folders are left in place.
+ (BOOL)deletePermanently:(NSData *)path error:(NSError **)error;

// Moves the item into directory, keeping its name and never replacing an
// existing entry. Within a filesystem this is a rename; across filesystems
// mv(1) copies and removes it.
+ (BOOL)moveItem:(NSData *)path toDirectory:(NSData *)directory error:(NSError **)error;

// The trash directories (each containing files/ and info/) that exist for
// this user: the home trash and the per-volume trashes of mounted
// filesystems.
+ (NSArray *)existingTrashDirectories;
// Permanently deletes everything in the given trash directories' files/ and
// info/ folders. Returns NO and the first error if anything was left.
+ (BOOL)emptyTrashDirectories:(NSArray *)trashDirectories error:(NSError **)error;

// The trash directory (containing files/ and info/) the item would be moved
// into, creating it if needed; nil if the item has no usable trash. Exposed
// for tests.
+ (NSData *)trashDirectoryForPath:(NSData *)path error:(NSError **)error;

// Percent-encodes a path for a .trashinfo Path= key or a file:// URI.
+ (NSString *)percentEncodedPath:(NSData *)path;

@end
