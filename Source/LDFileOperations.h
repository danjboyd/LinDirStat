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

// WinDirStat's Remove Empty Folders: removes the folder with rmdir(2), which
// only removes empty folders. Fails with ENOTDIR for anything but a real
// folder (a symlink to one included).
+ (BOOL)removeEmptyFolder:(NSData *)path error:(NSError **)error;
// WinDirStat's Change Folder Dates: sets a real folder's modification time
// (seconds since 1970), leaving its access time; never follows a symlink.
+ (BOOL)setModificationTime:(NSTimeInterval)seconds ofFolder:(NSData *)path error:(NSError **)error;
// YES when path is a real folder: not a symlink.
+ (BOOL)isRealFolder:(NSData *)path;
// YES for a folder macOS shows as one item: an app, a bundle or a document
// package such as a Photos library (NSURLIsPackageKey). Always NO on Linux.
+ (BOOL)isPackage:(NSData *)path;
// WinDirStat 2.8's Deduplicate with Hardlink (71143eb4): replaces target
// with a hard link to source. Both must be regular files (no symlinks) on
// one filesystem with the same contents, compared byte for byte now, so a
// file changed since the duplicate search is never lost (ECANCELED). The
// link is made under a temporary name in target's folder and renamed over
// target, so a failure leaves target as it was. Already the same file:
// nothing to do. The target takes source's permissions and owner, as any
// hard link does.
+ (BOOL)replaceFile:(NSData *)target withHardLinkTo:(NSData *)source error:(NSError **)error;

// The trash directories (each containing files/ and info/) that exist for
// this user: the home trash and the per-volume trashes of mounted
// filesystems.
+ (NSArray *)existingTrashDirectories;
// Permanently deletes everything in the given trash directories' files/ and
// info/ folders. Returns NO and the first error if anything was left.
+ (BOOL)emptyTrashDirectories:(NSArray *)trashDirectories error:(NSError **)error;

// macOS keeps its own trash, which Finder empties: the user's Trash folder
// (refreshed after trashing and emptying), or nil where the freedesktop.org
// trash is used.
+ (NSData *)systemTrashPath;
// Asks Finder to empty the Trash (every volume's). Blocking; the first time
// macOS asks the user to let LinDirStat control Finder.
+ (BOOL)emptySystemTrash:(NSError **)error;

// The folders holding trashed items: each existing freedesktop.org trash's
// files/ folder, or the macOS Trash.
+ (NSArray *)trashContentDirectories;
// What the Empty Trash menu item shows (WinDirStat's "(N Items, X)"): the
// items directly in the given folders and the physical size of everything
// below them. Never follows links; stops after entryLimit entries, setting
// complete to NO. items is NSNotFound when a folder exists but may not be
// read (macOS without Full Disk Access). Blocking; call it off the main
// thread.
+ (void)measureTrashContents:(NSArray *)directories
                  entryLimit:(NSUInteger)entryLimit
                       items:(NSUInteger *)items
                       bytes:(unsigned long long *)bytes
                    complete:(BOOL *)complete;

// The trash directory (containing files/ and info/) the item would be moved
// into, creating it if needed; nil if the item has no usable trash. Exposed
// for tests.
+ (NSData *)trashDirectoryForPath:(NSData *)path error:(NSError **)error;

// Percent-encodes a path for a .trashinfo Path= key or a file:// URI.
+ (NSString *)percentEncodedPath:(NSData *)path;

@end
