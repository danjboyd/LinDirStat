#import <Foundation/Foundation.h>

@class LDFileNode;

extern NSString *const LDCSVErrorDomain;

typedef enum {
  LDCSVErrorMalformed = 1,
  LDCSVErrorMissingColumn = 2,
  LDCSVErrorMissingParent = 3,
  LDCSVErrorNoRows = 4
} LDCSVErrorCode;

// WinDirStat's "Save Results To CSV" / "Load Results From CSV" format
// (CsvLoader.cpp). File I/O failures are reported in NSPOSIXErrorDomain,
// format problems in LDCSVErrorDomain.
@interface LDCSV : NSObject

// Writes root's tree as WinDirStat does: a quoted header line, then one row
// per node, each preceded by "\r\n" (no trailing newline), UTF-8 without a
// BOM. Rows are depth-first pre-order with siblings sorted
// case-insensitively. includeOwner adds the "Owner" column (looked up on
// disk with lstat, like WinDirStat's Owner column).
+ (BOOL)writeTree:(LDFileNode *)root
           toPath:(NSString *)path
     includeOwner:(BOOL)includeOwner
            error:(NSError **)error;

// Reads a CSV written by -writeTree:... or by WinDirStat (Windows paths are
// accepted) and returns a finished, totalled tree sorted by physical size.
// Only the CSV is read; nothing in the tree is looked up on disk.
+ (LDFileNode *)readTreeFromPath:(NSString *)path error:(NSError **)error;

// WinDirStat's duplicates export: "Hash Prefix","Name","Logical Size",
// "Physical Size","Last Change","Attributes", one row per file.
// groups holds LDDuplicateGroup objects.
+ (BOOL)writeDuplicateGroups:(NSArray *)groups toPath:(NSString *)path error:(NSError **)error;

@end
