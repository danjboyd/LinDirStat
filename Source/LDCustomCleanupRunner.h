#import <Foundation/Foundation.h>

@class LDCustomCleanup;

// Runs a WinDirStat "Custom Cleanup" (DirStatDoc.cpp CallUserDefinedCleanup)
// on items given by exact path bytes. Commands run with /bin/sh -c in the
// item's folder (a file's parent); placeholders are replaced with raw path
// bytes and are not quoted, as in WinDirStat.
@interface LDCustomCleanupRunner : NSObject

// The command bytes for one run: %sp and %sn (the current subfolder when
// recursing) are replaced first, then %p (the item's path) and %n (its
// name). A '%' inside a substituted path is never expanded again.
+ (NSData *)commandForTemplate:(NSString *)commandTemplate
                          path:(NSData *)path
                 subfolderPath:(NSData *)subfolderPath;

// The folders a recursive cleanup visits for a folder: every subfolder,
// depth first and children before their parent, ending with the folder
// itself. Symlinks and other filesystems are not entered.
+ (NSArray *)recursionOrderForFolder:(NSData *)folder;

// The folder a command for path runs in.
+ (NSData *)workingDirectoryForPath:(NSData *)path isDirectory:(BOOL)isDirectory;

// Runs cleanup for each path (NSData) on a background queue, one after
// another. When the cleanup waits for completion, completion receives the
// paths whose commands ran (for refreshing); otherwise it receives them as
// soon as the commands started. Commands run in a terminal when the
// cleanup asks for it.
+ (void)runCleanup:(LDCustomCleanup *)cleanup
           onPaths:(NSArray *)paths
       directories:(NSArray *)isDirectoryFlags
        completion:(void (^)(NSArray *ranPaths, NSArray *failures))completion;

@end
