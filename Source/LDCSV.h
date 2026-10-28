#import <Foundation/Foundation.h>

@class LDFileNode;

extern NSString *const LDCSVErrorDomain;

typedef enum {
  LDCSVErrorMalformed = 1,
  LDCSVErrorMissingColumn = 2,
  LDCSVErrorMissingParent = 3,
  LDCSVErrorNoRows = 4
} LDCSVErrorCode;

// WinDirStat's "Save Results To CSV/JSON" / "Load Results From CSV/JSON"
// formats (CsvLoader.cpp). As in WinDirStat 2.6, a path ending in ".json"
// (any case) is JSON: an array of objects keyed by the CSV's column names,
// counts and sizes as numbers, everything else as strings. File I/O
// failures are reported in NSPOSIXErrorDomain, format problems in
// LDCSVErrorDomain.
@interface LDCSV : NSObject

// YES for a ".json" path, which the methods below read or write as JSON.
+ (BOOL)isJSONPath:(NSString *)path;

// Writes root's tree as WinDirStat does: a quoted header line, then one row
// per node, each preceded by "\r\n" (no trailing newline), UTF-8 without a
// BOM. Rows are depth-first pre-order with siblings sorted
// case-insensitively. includeOwner adds the "Owner" column (looked up on
// disk with lstat, like WinDirStat's Owner column). As in WinDirStat, the
// "<Hardlinks>" folders are left out and hard links are written undone: each
// link with the file's sizes, each folder with all the links below it. Index
// is the inode (looked up with lstat when writing).
+ (BOOL)writeTree:(LDFileNode *)root
           toPath:(NSString *)path
     includeOwner:(BOOL)includeOwner
            error:(NSError **)error;

// Reads a CSV written by -writeTree:... or by WinDirStat (Windows paths are
// accepted) and returns a finished, totalled tree sorted by physical size.
// Only the CSV is read; nothing in the tree is looked up on disk. Files with
// the same non-zero Index are links to one file and counted once; with
// processHardLinks they are shown under "<Hardlinks>" (see LDHardLinks.h).
// Files with Index 0 (older LinDirStat files) are taken as written.
+ (LDFileNode *)readTreeFromPath:(NSString *)path processHardLinks:(BOOL)processHardLinks error:(NSError **)error;
// The same with processHardLinks YES.
+ (LDFileNode *)readTreeFromPath:(NSString *)path error:(NSError **)error;

// WinDirStat's duplicates export: "Hash Prefix","Name","Logical Size",
// "Physical Size","Last Change","Attributes","Sampled hash", one row per
// file. Sampled hash is always false: LinDirStat hashes whole files.
// groups holds LDDuplicateGroup objects.
+ (BOOL)writeDuplicateGroups:(NSArray *)groups toPath:(NSString *)path error:(NSError **)error;

@end
