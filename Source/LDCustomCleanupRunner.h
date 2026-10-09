#import <Foundation/Foundation.h>

@class LDCustomCleanup;

// Runs a WinDirStat "Custom Cleanup" (DirStatDoc.cpp CallUserDefinedCleanup)
// on items given by exact path bytes. Commands run with /bin/sh -c in the
// item's folder (a file's parent).
//
// WinDirStat pastes paths into the command line unquoted. Linux names can
// contain quotes, '$' and newlines, so here the placeholders become shell
// parameters instead and the paths are passed as arguments: %p is "$1",
// %n "$2", %sp "$3" and %sn "$4". A placeholder the template already wraps
// in double quotes ("%p", as WinDirStat users write it) is not quoted again.
@interface LDCustomCleanupRunner : NSObject

// The shell script for a command template.
+ (NSString *)scriptForTemplate:(NSString *)commandTemplate;

// The full command: /bin/sh -c script with the path, name, subfolder path
// and subfolder name as $1..$4 (the subfolder is the path itself when not
// recursing).
+ (NSArray *)commandForTemplate:(NSString *)commandTemplate
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
