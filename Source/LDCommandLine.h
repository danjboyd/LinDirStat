#import <Foundation/Foundation.h>

@class LDScanOptions;

// WinDirStat's command line (WinDirStat.cpp, CWinDirStatCommandLineInfo):
//
//   LinDirStat [folder...]                      scan the folders
//   LinDirStat --saveto FILE folder...          scan, save results, exit
//   LinDirStat --savedupesto FILE folder...     the same for duplicates
//   LinDirStat --loadfrom FILE                  show saved results
//
// FILE is JSON when it ends in ".json" and CSV otherwise (WinDirStat 2.6).
// The older names --savetocsv, --savedupestocsv and --loadfromcsv still
// work.
//
// Flags are case-insensitive and may also be spelled -flag or /flag, as on
// Windows. Several folders scan under "This Computer". Folders that do not
// exist are ignored, as WinDirStat ignores them. Other "-Key value" pairs
// are GNUstep/Cocoa defaults and are skipped.
@interface LDCommandLine : NSObject
{
  NSMutableArray *_scanPaths;
  NSMutableArray *_ignoredPaths;
  NSString *_saveToCSVPath;
  NSString *_saveDuplicatesToCSVPath;
  NSString *_loadFromCSVPath;
  NSString *_errorMessage;
  BOOL _headless;
}

// arguments includes the program name first, like -[NSProcessInfo
// arguments]. Relative paths are taken against currentDirectory.
+ (LDCommandLine *)commandLineWithArguments:(NSArray *)arguments currentDirectory:(NSString *)currentDirectory;
// This process's command line.
+ (LDCommandLine *)processCommandLine;

// Absolute, standardized paths of existing folders, in the order given.
- (NSArray *)scanPaths;
// Path arguments that are not existing folders.
- (NSArray *)ignoredPaths;
// Absolute paths, or nil when the flag was not given.
- (NSString *)saveToCSVPath;
- (NSString *)saveDuplicatesToCSVPath;
- (NSString *)loadFromCSVPath;
// Set when a flag is missing its file name.
- (NSString *)errorMessage;

// YES when either save flag was given (even without its file name):
// results are saved without showing a window.
- (BOOL)isHeadless;

@end

// Runs a headless command line with Foundation only, so no display is
// needed: scans the folders with options (duplicate detection on only for
// --savedupesto, as in WinDirStat), writes the CSV or JSON files and returns the
// exit status, 0 when every file was written and 1 otherwise
// (DirStatDoc.cpp). Problems are added to messages as lines for stderr.
@interface LDCommandLineExport : NSObject

+ (int)runCommandLine:(LDCommandLine *)commandLine
          scanOptions:(LDScanOptions *)options
         includeOwner:(BOOL)includeOwner
             messages:(NSMutableArray *)messages;

@end
