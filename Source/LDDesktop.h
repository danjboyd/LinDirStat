#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

// Hands items to the desktop: the default application, the file manager and
// a terminal. A command is an NSArray whose first element is the program name
// (NSString) and whose other elements are arguments (NSString, or NSData for
// exact filesystem bytes). Paths are exact bytes (-[LDFileNode pathData]).
@interface LDDesktop : NSObject

// Commands tried in order until one succeeds.
+ (NSArray *)openCommandsForPath:(NSData *)path;
+ (NSArray *)revealCommandsForPath:(NSData *)path;
// Opens a web address in the default browser.
+ (NSArray *)openCommandsForURL:(NSString *)url;
// Terminals run with the folder as their working directory too.
+ (NSArray *)terminalCommandsForDirectory:(NSData *)directory;
// Terminals running command (an argument list as above) and closing when it
// ends; they wait for it, so the terminal exits when the command does.
+ (NSArray *)terminalCommandsRunning:(NSArray *)command inDirectory:(NSData *)directory;

// file:// URI for a path, percent-encoding every byte that needs it.
+ (NSString *)fileURIForPath:(NSData *)path;

// The full path of an executable found on $PATH, or nil.
+ (NSString *)pathOfExecutable:(NSString *)name;

// Runs commands in order on a background queue until one exits with status
// 0; programs that are not installed are skipped. completion runs on the
// main queue. directory, if given, is the working directory.
+ (void)runFirstSuccessfulCommand:(NSArray *)commands
                      inDirectory:(NSData *)directory
                       completion:(void (^)(BOOL succeeded))completion;
// As above, with completion on queue; nil runs it on the background queue
// that ran the commands.
+ (void)runFirstSuccessfulCommand:(NSArray *)commands
                      inDirectory:(NSData *)directory
                            queue:(dispatch_queue_t)queue
                       completion:(void (^)(BOOL succeeded))completion;

// Starts the first installed command without waiting for it to exit (for
// long-running programs such as terminals). Returns NO if none could start.
+ (BOOL)launchFirstAvailableCommand:(NSArray *)commands inDirectory:(NSData *)directory;

@end
