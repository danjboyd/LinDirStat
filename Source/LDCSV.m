#import "LDCSV.h"
#import "LDDuplicateFinder.h"
#import "LDFileAttributes.h"
#import "LDFileNode.h"
#import "LDHardLinks.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <time.h>

NSString *const LDCSVErrorDomain = @"LDCSVErrorDomain";

// WinDirStat item-type bits (Item.h ITEMTYPE) used in the
// "WinDirStat Attributes" column.
enum {
  LDCSVTypeMyComputer = 0x1,
  LDCSVTypeDrive = 0x2,
  LDCSVTypeDirectory = 0x4,
  LDCSVTypeFile = 0x8,
  LDCSVTypeFreeSpace = 0x10,
  LDCSVTypeUnknown = 0x20,
  LDCSVTypeRoot = 0x10000000,
  LDCSVTypeDone = 0x20000000
};

// Column order of a written file; the reader matches columns by name.
enum {
  LDCSVColumnName,
  LDCSVColumnFiles,
  LDCSVColumnFolders,
  LDCSVColumnLogicalSize,
  LDCSVColumnPhysicalSize,
  LDCSVColumnAttributes,
  LDCSVColumnLastChange,
  LDCSVColumnWinDirStatAttributes,
  LDCSVColumnIndex,
  LDCSVColumnOwner,
  LDCSVColumnCount
};

static NSString *const LDCSVColumnNames[LDCSVColumnCount] = {
  @"Name", @"Files", @"Folders", @"Logical Size", @"Physical Size",
  @"Attributes", @"Last Change", @"WinDirStat Attributes", @"Index", @"Owner"
};

static NSError *LDCSVError(LDCSVErrorCode code, NSString *description)
{
  return [NSError errorWithDomain:LDCSVErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey: description}];
}

static NSError *LDCSVPOSIXError(int code, NSString *step)
{
  NSString *description = [NSString stringWithFormat:@"%@: %s", step, strerror(code)];
  return [NSError errorWithDomain:NSPOSIXErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey: description}];
}

#pragma mark - Writing

static BOOL LDIsValidUTF8(const unsigned char *bytes, size_t length)
{
  size_t i = 0;
  while (i < length) {
    unsigned char c = bytes[i];
    size_t extra = 0;
    uint32_t minimum = 0;
    uint32_t value = 0;
    if (c < 0x80) {
      i++;
      continue;
    } else if ((c & 0xE0) == 0xC0) {
      extra = 1; minimum = 0x80; value = c & 0x1F;
    } else if ((c & 0xF0) == 0xE0) {
      extra = 2; minimum = 0x800; value = c & 0x0F;
    } else if ((c & 0xF8) == 0xF0) {
      extra = 3; minimum = 0x10000; value = c & 0x07;
    } else {
      return NO;
    }
    if (i + extra >= length) {
      return NO;
    }
    size_t k = 0;
    for (k = 1; k <= extra; k++) {
      unsigned char next = bytes[i + k];
      if ((next & 0xC0) != 0x80) {
        return NO;
      }
      value = (value << 6) | (next & 0x3F);
    }
    if (value < minimum || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF)) {
      return NO;
    }
    i += extra + 1;
  }
  return YES;
}

// Writes bytes as a quoted field. Embedded quotes are doubled, which
// WinDirStat does not do (Windows names cannot contain '"', Linux names can).
static void LDWriteQuoted(FILE *file, const char *bytes, size_t length)
{
  fputc('"', file);
  size_t start = 0;
  size_t i = 0;
  for (i = 0; i < length; i++) {
    if (bytes[i] == '"') {
      fwrite(bytes + start, 1, i + 1 - start, file);
      fputc('"', file);
      start = i + 1;
    }
  }
  fwrite(bytes + start, 1, length - start, file);
  fputc('"', file);
}

static void LDWriteQuotedString(FILE *file, NSString *string)
{
  const char *bytes = [string UTF8String];
  LDWriteQuoted(file, bytes ? bytes : "", bytes ? strlen(bytes) : 0);
}

// Writes bytes as a JSON string. WinDirStat escapes only '"' and '\\'
// (CsvLoader.cpp JsonQuote); control characters, which Windows names cannot
// hold but Linux names can, are written as \u00XX so the file stays JSON.
static void LDWriteJSONQuoted(FILE *file, const char *bytes, size_t length)
{
  fputc('"', file);
  size_t start = 0;
  size_t i = 0;
  for (i = 0; i < length; i++) {
    unsigned char c = (unsigned char)bytes[i];
    if (c != '"' && c != '\\' && c >= 0x20) {
      continue;
    }
    fwrite(bytes + start, 1, i - start, file);
    if (c == '"' || c == '\\') {
      fputc('\\', file);
      fputc(c, file);
    } else {
      fprintf(file, "\\u%04x", c);
    }
    start = i + 1;
  }
  fwrite(bytes + start, 1, length - start, file);
  fputc('"', file);
}

static void LDWriteJSONQuotedString(FILE *file, NSString *string)
{
  const char *bytes = [string UTF8String];
  LDWriteJSONQuoted(file, bytes ? bytes : "", bytes ? strlen(bytes) : 0);
}

// A text field in either format.
static void LDWriteText(FILE *file, BOOL json, const char *bytes, size_t length)
{
  if (json) {
    LDWriteJSONQuoted(file, bytes, length);
  } else {
    LDWriteQuoted(file, bytes, length);
  }
}

static void LDWriteTextString(FILE *file, BOOL json, NSString *string)
{
  if (json) {
    LDWriteJSONQuotedString(file, string);
  } else {
    LDWriteQuotedString(file, string);
  }
}

// A JSON member's key: two spaces, the column name and ": ", as WinDirStat
// writes them, each member after the first on its own line.
static void LDWriteJSONKey(FILE *file, NSString *name, BOOL first)
{
  fputs(first ? "  " : ",\r\n  ", file);
  LDWriteJSONQuotedString(file, name);
  fputs(": ", file);
}

static NSComparisonResult LDCompareNamesCaseInsensitively(id left, id right, void *context)
{
  (void)context;
  const char *leftName = [(LDFileNode *)left nameBytes];
  const char *rightName = [(LDFileNode *)right nameBytes];
  int order = strcasecmp(leftName, rightName);
  if (order == 0) {
    order = strcmp(leftName, rightName);
  }
  return order < 0 ? NSOrderedAscending : (order > 0 ? NSOrderedDescending : NSOrderedSame);
}

// What a row's sizes differ from the tree's: WinDirStat undoes its hard-link
// de-duplication in the CSV (CsvLoader.cpp:284-315), so every link carries
// the file's sizes and every folder those of all the links below it, while
// the "<Hardlinks>" folders (which are not written) no longer count.
typedef struct {
  long long logical;
  long long physical;
} LDCSVSizeDelta;

typedef struct {
  __unsafe_unretained LDHardLinkTable *hardLinks;
  __unsafe_unretained NSMapTable *folderDeltas;
  BOOL includeOwner;
  // WinDirStat 2.6's JSON layout (CsvLoader.cpp SaveResultsJson) instead of
  // CSV rows; firstRow is cleared once a row is written.
  BOOL json;
  BOOL firstRow;
} LDCSVWriteContext;

static void LDAddDeltaUpward(NSMapTable *deltas, LDFileNode *node, LDFileNode *root, long long logical, long long physical)
{
  for (LDFileNode *cursor = node; cursor; cursor = [cursor parent]) {
    LDCSVSizeDelta delta = {0, 0};
    NSData *stored = [deltas objectForKey:cursor];
    if (stored) {
      memcpy(&delta, [stored bytes], sizeof(delta));
    }
    delta.logical += logical;
    delta.physical += physical;
    [deltas setObject:[NSData dataWithBytes:&delta length:sizeof(delta)] forKey:cursor];
    if (cursor == root) {
      break;
    }
  }
}

static NSMapTable *LDFolderDeltasForTree(LDFileNode *root, LDHardLinkTable *hardLinks)
{
  NSMapTable *deltas = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality
                                             valueOptions:NSPointerFunctionsStrongMemory];
  for (LDHardLinkSet *set in [hardLinks sets]) {
    for (LDFileNode *link in [set members]) {
      if (link != root && [root isAncestorOf:link]) {
        LDAddDeltaUpward(deltas, [link parent], root,
                         (long long)[set size] - (long long)[link aggregateSize],
                         (long long)[set allocatedSize] - (long long)[link aggregateAllocatedSize]);
      }
    }
  }
  NSArray *scanRoots = [root isComputer] ? [root children] : @[root];
  for (LDFileNode *scanRoot in scanRoots) {
    LDFileNode *container = [LDHardLinks containerForNode:scanRoot];
    if (container && [container parent] == scanRoot) {
      LDAddDeltaUpward(deltas, scanRoot, root, -(long long)[container aggregateSize], -(long long)[container aggregateAllocatedSize]);
    }
  }
  return deltas;
}

// Index is WinDirStat's file ID: the inode, looked up when writing so the
// tree does not have to keep it.
static unsigned long long LDIndexForPath(NSData *path)
{
  if ([path length] == 0) {
    return 0;
  }
  NSMutableData *terminated = [path mutableCopy];
  [terminated appendBytes:"" length:1];
  struct stat info;
  return lstat([terminated bytes], &info) == 0 ? (unsigned long long)info.st_ino : 0;
}

static void LDWriteRow(FILE *file, LDFileNode *node, NSData *path, BOOL isRoot, LDCSVWriteContext *context)
{
  BOOL isDirectory = [node kind] == LDFileNodeKindDirectory;
  BOOL includeOwner = context->includeOwner;
  BOOL json = context->json;

  if (json) {
    fputs(context->firstRow ? "{\r\n" : ",\r\n{\r\n", file);
    LDWriteJSONKey(file, LDCSVColumnNames[LDCSVColumnName], YES);
  } else {
    fputs("\r\n", file);
  }
  context->firstRow = NO;
  if ([node isComputer]) {
    LDWriteTextString(file, json, [node path]);
  } else if (LDIsValidUTF8([path bytes], [path length])) {
    LDWriteText(file, json, [path bytes], [path length]);
  } else {
    // The text is UTF-8, so a path that is not falls back to -path, which
    // decodes such names as Latin-1. It will not match the name on disk.
    LDWriteTextString(file, json, [node path]);
  }

  // WinDirStat writes 0/0 for files, and for folders the files and
  // subfolders below them (not counting the folder itself).
  unsigned long files = 0;
  unsigned long folders = 0;
  if (isDirectory) {
    files = (unsigned long)[node fileCount];
    folders = [node directoryCount] > 0 ? (unsigned long)[node directoryCount] - 1 : 0;
  }
  unsigned long long logical = [node aggregateSize];
  unsigned long long physical = [node aggregateAllocatedSize];
  unsigned long long index = 0;
  LDHardLinkSet *set = isDirectory ? nil : [context->hardLinks setForNode:node];
  if (set) {
    logical = [set size];
    physical = [set allocatedSize];
    index = [set inode];
  } else {
    NSData *stored = isDirectory ? [context->folderDeltas objectForKey:node] : nil;
    if (stored) {
      LDCSVSizeDelta delta;
      memcpy(&delta, [stored bytes], sizeof(delta));
      logical = (unsigned long long)((long long)logical + delta.logical);
      physical = (unsigned long long)((long long)physical + delta.physical);
    }
    index = [node isComputer] ? 0 : LDIndexForPath(path);
  }
  NSString *attributes = [LDFileAttributes attributeStringForNode:node];

  time_t seconds = (time_t)[node aggregateModificationTime];
  struct tm utc;
  memset(&utc, 0, sizeof(utc));
  gmtime_r(&seconds, &utc);
  char lastChange[32];
  snprintf(lastChange, sizeof(lastChange), "%04d-%02d-%02dT%02d:%02d:%02dZ",
           utc.tm_year + 1900, utc.tm_mon + 1, utc.tm_mday, utc.tm_hour, utc.tm_min, utc.tm_sec);
  // Symlinks and special files are written as files.
  unsigned int type = isDirectory ? LDCSVTypeDirectory : LDCSVTypeFile;
  if ([node kind] == LDFileNodeKindFreeSpace) {
    type = LDCSVTypeFreeSpace;
  } else if ([node kind] == LDFileNodeKindUnknown) {
    type = LDCSVTypeUnknown;
  } else if ([node isComputer]) {
    type = LDCSVTypeMyComputer;
  } else if (isDirectory && [[node parent] isComputer]) {
    // The roots of a multi-root scan are WinDirStat's drives.
    type = LDCSVTypeDrive;
  }
  if (isRoot) {
    type |= LDCSVTypeRoot;
  }
  if (![node isScanPending]) {
    type |= LDCSVTypeDone;
  }
  NSString *owner = includeOwner ? ([node isSpaceItem] ? @"" : [LDFileAttributes ownerOfPath:path]) : nil;

  if (json) {
    // Counts and sizes are numbers; the rest are strings, the type and
    // index included ("0x00000008").
    LDWriteJSONKey(file, LDCSVColumnNames[LDCSVColumnFiles], NO);
    fprintf(file, "%lu", files);
    LDWriteJSONKey(file, LDCSVColumnNames[LDCSVColumnFolders], NO);
    fprintf(file, "%lu", folders);
    LDWriteJSONKey(file, LDCSVColumnNames[LDCSVColumnLogicalSize], NO);
    fprintf(file, "%llu", logical);
    LDWriteJSONKey(file, LDCSVColumnNames[LDCSVColumnPhysicalSize], NO);
    fprintf(file, "%llu", physical);
    LDWriteJSONKey(file, LDCSVColumnNames[LDCSVColumnAttributes], NO);
    LDWriteJSONQuotedString(file, attributes);
    LDWriteJSONKey(file, LDCSVColumnNames[LDCSVColumnLastChange], NO);
    fprintf(file, "\"%s\"", lastChange);
    LDWriteJSONKey(file, LDCSVColumnNames[LDCSVColumnWinDirStatAttributes], NO);
    fprintf(file, "\"0x%08X\"", type);
    LDWriteJSONKey(file, LDCSVColumnNames[LDCSVColumnIndex], NO);
    fprintf(file, "\"0x%016llX\"", index);
    if (includeOwner) {
      LDWriteJSONKey(file, LDCSVColumnNames[LDCSVColumnOwner], NO);
      LDWriteJSONQuotedString(file, owner);
    }
    fputs("\r\n}", file);
    return;
  }

  fprintf(file, ",%lu,%lu,%llu,%llu,", files, folders, logical, physical);
  LDWriteQuotedString(file, attributes);
  fprintf(file, ",%s,0x%08X,0x%016llX", lastChange, type, index);
  if (includeOwner) {
    fputc(',', file);
    LDWriteQuotedString(file, owner);
  }
}

static void LDWriteSubtree(FILE *file, LDFileNode *node, NSMutableData *path, BOOL isRoot, LDCSVWriteContext *context)
{
  if (LDIsHardLinkItem(node)) {
    return;
  }
  LDWriteRow(file, node, path, isRoot, context);
  NSArray *children = [node children];
  if ([children count] == 0) {
    return;
  }
  children = [children sortedArrayUsingFunction:LDCompareNamesCaseInsensitively context:NULL];
  NSUInteger parentLength = [path length];
  // A Windows tree loaded from a WinDirStat CSV keeps its backslashes.
  char separator = [node pathSeparator];
  BOOL needsSeparator = parentLength == 0 || ((const char *)[path bytes])[parentLength - 1] != separator;
  for (LDFileNode *child in children) {
    if ([node isComputer]) {
      // Its children are full-path roots.
      LDWriteSubtree(file, child, [[child pathData] mutableCopy], NO, context);
      continue;
    }
    if (needsSeparator) {
      [path appendBytes:&separator length:1];
    }
    const char *name = [child nameBytes];
    [path appendBytes:name length:strlen(name)];
    LDWriteSubtree(file, child, path, NO, context);
    [path setLength:parentLength];
  }
}

#pragma mark - Reading

// One parsed record: each field is copied (quotes removed, doubled quotes
// collapsed) into storage and NUL-terminated, so numeric fields can go
// straight to strtoull.
typedef struct {
  size_t offset;
  size_t length;
} LDCSVField;

typedef struct {
  const unsigned char *bytes;
  size_t length;
  size_t position;
  NSMutableData *storage;
  NSMutableData *fields;
  // WinDirStat 2.6's JSON results (an array of objects keyed by column
  // name) read as records: first a header of every column, then one record
  // per object with its values in that order.
  BOOL json;
  BOOL headerRead;
} LDCSVParser;

static void LDParserAppendField(LDCSVParser *parser, size_t offset)
{
  LDCSVField field = {offset, [parser->storage length] - offset};
  [parser->storage appendBytes:"\0" length:1];
  [parser->fields appendBytes:&field length:sizeof(field)];
}

// Reads the next non-empty record. Returns 1 for a record, 0 at the end of
// the input and -1 for an unterminated quoted field. Rows may be separated
// by "\r\n" before or after them (or bare "\n"), and quoted fields may hold
// commas and line breaks.
static int LDJSONNextRecord(LDCSVParser *parser);

static int LDParserNextRecord(LDCSVParser *parser)
{
  if (parser->json) {
    return LDJSONNextRecord(parser);
  }
  const unsigned char *bytes = parser->bytes;
  size_t length = parser->length;
  size_t pos = parser->position;
  [parser->storage setLength:0];
  [parser->fields setLength:0];

  while (pos < length && (bytes[pos] == '\r' || bytes[pos] == '\n')) {
    pos++;
  }
  if (pos >= length) {
    parser->position = pos;
    return 0;
  }

  while (YES) {
    size_t offset = [parser->storage length];
    if (pos < length && bytes[pos] == '"') {
      pos++;
      BOOL closed = NO;
      while (pos < length) {
        unsigned char c = bytes[pos];
        if (c != '"') {
          size_t start = pos;
          while (pos < length && bytes[pos] != '"') {
            pos++;
          }
          [parser->storage appendBytes:bytes + start length:pos - start];
          continue;
        }
        if (pos + 1 < length && bytes[pos + 1] == '"') {
          [parser->storage appendBytes:"\"" length:1];
          pos += 2;
        } else if (pos + 1 >= length || bytes[pos + 1] == ',' || bytes[pos + 1] == '\r' || bytes[pos + 1] == '\n') {
          pos++;
          closed = YES;
          break;
        } else {
          // A stray quote inside a quoted field: keep it as text.
          [parser->storage appendBytes:"\"" length:1];
          pos++;
        }
      }
      if (!closed) {
        parser->position = pos;
        return -1;
      }
    } else {
      size_t start = pos;
      while (pos < length && bytes[pos] != ',' && bytes[pos] != '\r' && bytes[pos] != '\n') {
        pos++;
      }
      [parser->storage appendBytes:bytes + start length:pos - start];
    }
    LDParserAppendField(parser, offset);
    if (pos < length && bytes[pos] == ',') {
      pos++;
      continue;
    }
    break;
  }
  parser->position = pos;
  return 1;
}

#pragma mark JSON

static void LDJSONSkipSpace(LDCSVParser *parser)
{
  while (parser->position < parser->length) {
    unsigned char c = parser->bytes[parser->position];
    if (c != ' ' && c != '\t' && c != '\r' && c != '\n') {
      break;
    }
    parser->position++;
  }
}

static void LDAppendUTF8(NSMutableData *data, uint32_t value)
{
  unsigned char bytes[4];
  size_t length = 0;
  if (value < 0x80) {
    bytes[0] = (unsigned char)value;
    length = 1;
  } else if (value < 0x800) {
    bytes[0] = (unsigned char)(0xC0 | (value >> 6));
    bytes[1] = (unsigned char)(0x80 | (value & 0x3F));
    length = 2;
  } else if (value < 0x10000) {
    bytes[0] = (unsigned char)(0xE0 | (value >> 12));
    bytes[1] = (unsigned char)(0x80 | ((value >> 6) & 0x3F));
    bytes[2] = (unsigned char)(0x80 | (value & 0x3F));
    length = 3;
  } else {
    bytes[0] = (unsigned char)(0xF0 | (value >> 18));
    bytes[1] = (unsigned char)(0x80 | ((value >> 12) & 0x3F));
    bytes[2] = (unsigned char)(0x80 | ((value >> 6) & 0x3F));
    bytes[3] = (unsigned char)(0x80 | (value & 0x3F));
    length = 4;
  }
  [data appendBytes:bytes length:length];
}

static BOOL LDJSONReadHex4(LDCSVParser *parser, uint32_t *value)
{
  if (parser->position + 4 > parser->length) {
    return NO;
  }
  uint32_t result = 0;
  size_t i = 0;
  for (i = 0; i < 4; i++) {
    unsigned char c = parser->bytes[parser->position + i];
    result <<= 4;
    if (c >= '0' && c <= '9') {
      result |= (uint32_t)(c - '0');
    } else if (c >= 'a' && c <= 'f') {
      result |= (uint32_t)(c - 'a' + 10);
    } else if (c >= 'A' && c <= 'F') {
      result |= (uint32_t)(c - 'A' + 10);
    } else {
      return NO;
    }
  }
  parser->position += 4;
  *value = result;
  return YES;
}

// Reads a string (at its opening quote) into output, unescaped. Raw bytes,
// control characters included, are taken as they are, as WinDirStat's
// JsonReadObject does.
static BOOL LDJSONReadString(LDCSVParser *parser, NSMutableData *output)
{
  const unsigned char *bytes = parser->bytes;
  parser->position++;
  while (parser->position < parser->length) {
    size_t start = parser->position;
    while (parser->position < parser->length && bytes[parser->position] != '"' && bytes[parser->position] != '\\') {
      parser->position++;
    }
    [output appendBytes:bytes + start length:parser->position - start];
    if (parser->position >= parser->length) {
      return NO;
    }
    unsigned char c = bytes[parser->position++];
    if (c == '"') {
      return YES;
    }
    if (parser->position >= parser->length) {
      return NO;
    }
    unsigned char escaped = bytes[parser->position++];
    char simple = 0;
    switch (escaped) {
      case 'b': simple = '\b'; break;
      case 'f': simple = '\f'; break;
      case 'n': simple = '\n'; break;
      case 'r': simple = '\r'; break;
      case 't': simple = '\t'; break;
      case 'u': {
        uint32_t value = 0;
        if (!LDJSONReadHex4(parser, &value)) {
          return NO;
        }
        if (value >= 0xD800 && value <= 0xDBFF && parser->position + 1 < parser->length
            && bytes[parser->position] == '\\' && bytes[parser->position + 1] == 'u') {
          size_t mark = parser->position;
          uint32_t low = 0;
          parser->position += 2;
          if (LDJSONReadHex4(parser, &low) && low >= 0xDC00 && low <= 0xDFFF) {
            value = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00);
          } else {
            parser->position = mark;
          }
        }
        LDAppendUTF8(output, value);
        continue;
      }
      default:
        // '"', '\\', '/' and anything else stand for themselves.
        simple = (char)escaped;
        break;
    }
    [output appendBytes:&simple length:1];
  }
  return NO;
}

// Skips an array or object (at its opening bracket), strings included.
static BOOL LDJSONSkipNested(LDCSVParser *parser)
{
  NSUInteger depth = 0;
  NSMutableData *scratch = [NSMutableData data];
  while (parser->position < parser->length) {
    unsigned char c = parser->bytes[parser->position];
    if (c == '"') {
      [scratch setLength:0];
      if (!LDJSONReadString(parser, scratch)) {
        return NO;
      }
      continue;
    }
    parser->position++;
    if (c == '[' || c == '{') {
      depth++;
    } else if (c == ']' || c == '}') {
      if (depth == 0) {
        return NO;
      }
      if (--depth == 0) {
        return YES;
      }
    }
  }
  return NO;
}

// The next object's values, in column order; objects without a Name are
// skipped, as WinDirStat skips them. Returns 1, 0 at the array's end and -1
// when the text is not JSON.
static int LDJSONNextRecord(LDCSVParser *parser)
{
  const unsigned char *bytes = parser->bytes;
  NSUInteger column = 0;
  [parser->storage setLength:0];
  [parser->fields setLength:0];

  if (!parser->headerRead) {
    // Everything before the array is ignored (WinDirStat skips lines until
    // '[').
    while (parser->position < parser->length && bytes[parser->position] != '[') {
      parser->position++;
    }
    if (parser->position >= parser->length) {
      return 0;
    }
    parser->position++;
    parser->headerRead = YES;
    for (column = 0; column < LDCSVColumnCount; column++) {
      size_t offset = [parser->storage length];
      const char *name = [LDCSVColumnNames[column] UTF8String];
      [parser->storage appendBytes:name length:strlen(name)];
      LDParserAppendField(parser, offset);
    }
    return 1;
  }

  NSMutableData *key = [NSMutableData data];
  while (YES) {
    LDJSONSkipSpace(parser);
    if (parser->position < parser->length && bytes[parser->position] == ',') {
      parser->position++;
      LDJSONSkipSpace(parser);
    }
    if (parser->position >= parser->length || bytes[parser->position] == ']') {
      return 0;
    }
    if (bytes[parser->position] != '{') {
      return -1;
    }
    parser->position++;

    [parser->storage setLength:0];
    LDCSVField values[LDCSVColumnCount];
    BOOL present[LDCSVColumnCount];
    memset(present, 0, sizeof(present));
    while (YES) {
      LDJSONSkipSpace(parser);
      if (parser->position >= parser->length) {
        return -1;
      }
      if (bytes[parser->position] == '}') {
        parser->position++;
        break;
      }
      if (bytes[parser->position] != '"') {
        return -1;
      }
      [key setLength:0];
      if (!LDJSONReadString(parser, key)) {
        return -1;
      }
      LDJSONSkipSpace(parser);
      if (parser->position >= parser->length || bytes[parser->position] != ':') {
        return -1;
      }
      parser->position++;
      LDJSONSkipSpace(parser);
      if (parser->position >= parser->length) {
        return -1;
      }
      size_t offset = [parser->storage length];
      if (bytes[parser->position] == '"') {
        if (!LDJSONReadString(parser, parser->storage)) {
          return -1;
        }
      } else if (bytes[parser->position] == '[' || bytes[parser->position] == '{') {
        // A nested array or object (WinDirStat writes none): skipped, its
        // column read as empty.
        if (!LDJSONSkipNested(parser)) {
          return -1;
        }
      } else {
        // A number, true, false or null, kept as its text.
        size_t start = parser->position;
        while (parser->position < parser->length && bytes[parser->position] != ',' && bytes[parser->position] != '}'
               && bytes[parser->position] != ' ' && bytes[parser->position] != '\t'
               && bytes[parser->position] != '\r' && bytes[parser->position] != '\n') {
          parser->position++;
        }
        if (parser->position == start) {
          return -1;
        }
        [parser->storage appendBytes:bytes + start length:parser->position - start];
      }
      LDCSVField value = {offset, [parser->storage length] - offset};
      [parser->storage appendBytes:"\0" length:1];
      for (column = 0; column < LDCSVColumnCount; column++) {
        const char *name = [LDCSVColumnNames[column] UTF8String];
        if ([key length] == strlen(name) && memcmp([key bytes], name, [key length]) == 0) {
          values[column] = value;
          present[column] = YES;
        }
      }
      LDJSONSkipSpace(parser);
      if (parser->position < parser->length && bytes[parser->position] == ',') {
        parser->position++;
      } else if (parser->position >= parser->length || bytes[parser->position] != '}') {
        return -1;
      }
    }
    if (!present[LDCSVColumnName]) {
      continue;
    }
    // Missing columns read as empty, as in WinDirStat.
    size_t empty = [parser->storage length];
    [parser->storage appendBytes:"\0" length:1];
    for (column = 0; column < LDCSVColumnCount; column++) {
      LDCSVField field = present[column] ? values[column] : (LDCSVField){empty, 0};
      [parser->fields appendBytes:&field length:sizeof(field)];
    }
    return 1;
  }
}

static NSUInteger LDParserFieldCount(LDCSVParser *parser)
{
  return [parser->fields length] / sizeof(LDCSVField);
}

static const char *LDParserField(LDCSVParser *parser, NSUInteger index, size_t *length)
{
  const LDCSVField *field = (const LDCSVField *)[parser->fields bytes] + index;
  if (length) {
    *length = field->length;
  }
  return (const char *)[parser->storage bytes] + field->offset;
}

static NSString *LDStringFromBytes(const char *bytes, size_t length)
{
  NSString *string = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
  if (!string) {
    string = [[NSString alloc] initWithBytes:bytes length:length encoding:NSISOLatin1StringEncoding];
  }
  return string;
}

// "YYYY-MM-DDTHH:MM:SSZ" in UTC; 0 if it does not parse.
static int64_t LDParseTime(const char *text, size_t length)
{
  int year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0;
  if (length < 19 || text[10] != 'T'
      || sscanf(text, "%4d-%2d-%2dT%2d:%2d:%2d", &year, &month, &day, &hour, &minute, &second) != 6) {
    return 0;
  }
  struct tm utc;
  memset(&utc, 0, sizeof(utc));
  utc.tm_year = year - 1900;
  utc.tm_mon = month - 1;
  utc.tm_mday = day;
  utc.tm_hour = hour;
  utc.tm_min = minute;
  utc.tm_sec = second;
  return (int64_t)timegm(&utc);
}

// The mode cannot be recovered from the letters; this one makes R round-trip.
static unsigned int LDModeForRow(BOOL isDirectory, const char *attributes)
{
  BOOL readOnly = strchr(attributes, 'R') != NULL;
  if (isDirectory) {
    return S_IFDIR | (readOnly ? 0555 : 0755);
  }
  return S_IFREG | (readOnly ? 0444 : 0644);
}

// Registers a folder's path for parent lookups, also without a trailing
// separator, so children of "/" (parent "") and of "C:\" (parent "C:") find
// it, as WinDirStat's drive special case does.
static void LDRegisterParent(NSMutableDictionary *parents, LDFileNode *node, const char *path, size_t length, char separator)
{
  [parents setObject:node forKey:[NSData dataWithBytes:path length:length]];
  if (length > 0 && path[length - 1] == separator) {
    [parents setObject:node forKey:[NSData dataWithBytes:path length:length - 1]];
  }
}

static NSString *LDRowDescription(NSUInteger row)
{
  return [NSString stringWithFormat:@"row %lu", (unsigned long)row];
}

@interface LDCSV ()
+ (LDFileNode *)readTreeWithParser:(LDCSVParser *)parser processHardLinks:(BOOL)processHardLinks error:(NSError **)error;
@end

@implementation LDCSV

+ (BOOL)isJSONPath:(NSString *)path
{
  return [[[path pathExtension] lowercaseString] isEqualToString:@"json"];
}

+ (BOOL)writeTree:(LDFileNode *)root
           toPath:(NSString *)path
     includeOwner:(BOOL)includeOwner
            error:(NSError **)error
{
  if (!root) {
    if (error) {
      *error = LDCSVError(LDCSVErrorNoRows, @"There is no tree to save.");
    }
    return NO;
  }
  FILE *file = fopen([path fileSystemRepresentation], "wb");
  if (!file) {
    if (error) {
      *error = LDCSVPOSIXError(errno, [NSString stringWithFormat:@"Could not create %@", path]);
    }
    return NO;
  }
  setvbuf(file, NULL, _IOFBF, 256 * 1024);

  BOOL json = [self isJSONPath:path];
  if (json) {
    fputs("[\r\n", file);
  } else {
    NSUInteger columns = includeOwner ? LDCSVColumnCount : LDCSVColumnOwner;
    NSUInteger column = 0;
    for (column = 0; column < columns; column++) {
      if (column > 0) {
        fputc(',', file);
      }
      LDWriteQuotedString(file, LDCSVColumnNames[column]);
    }
  }

  @autoreleasepool {
    // The context does not retain these, and ARC may release a local after
    // its last use (it does at -O2 with Apple's clang), so keep them alive
    // until the end of the scope.
    __attribute__((objc_precise_lifetime)) LDHardLinkTable *hardLinks = [LDHardLinkTable tableForRoot:root];
    __attribute__((objc_precise_lifetime)) NSMapTable *folderDeltas = hardLinks ? LDFolderDeltasForTree(root, hardLinks) : nil;
    LDCSVWriteContext context = {hardLinks, folderDeltas, includeOwner, json, YES};
    NSMutableData *rootPath = [[root pathData] mutableCopy];
    LDWriteSubtree(file, root, rootPath, YES, &context);
  }
  if (json) {
    fputs("\r\n]\r\n", file);
  }

  BOOL failed = ferror(file) != 0;
  int writeErrno = errno;
  if (fclose(file) != 0 && !failed) {
    failed = YES;
    writeErrno = errno;
  }
  if (failed) {
    if (error) {
      *error = LDCSVPOSIXError(writeErrno ? writeErrno : EIO, [NSString stringWithFormat:@"Could not write %@", path]);
    }
    return NO;
  }
  return YES;
}

// WinDirStat's "Save Duplicates To CSV" (CsvLoader.cpp): one row per file,
// each followed by "\r\n", by logical size (descending), hash, then path.
+ (BOOL)writeDuplicateGroups:(NSArray *)groups toPath:(NSString *)path error:(NSError **)error
{
  NSMutableArray *rows = [NSMutableArray array];
  for (LDDuplicateGroup *group in groups) {
    for (LDFileNode *node in [group nodes]) {
      [rows addObject:@[group, node, [node path]]];
    }
  }
  [rows sortUsingComparator:^NSComparisonResult(NSArray *left, NSArray *right) {
    unsigned long long a = [[left objectAtIndex:0] logicalSize];
    unsigned long long b = [[right objectAtIndex:0] logicalSize];
    if (a != b) {
      return a > b ? NSOrderedAscending : NSOrderedDescending;
    }
    NSComparisonResult result = [[[left objectAtIndex:0] hashString] compare:[[right objectAtIndex:0] hashString]];
    return result != NSOrderedSame ? result : [[left objectAtIndex:2] caseInsensitiveCompare:[right objectAtIndex:2]];
  }];

  FILE *file = fopen([path fileSystemRepresentation], "wb");
  if (!file) {
    if (error) {
      *error = LDCSVPOSIXError(errno, [NSString stringWithFormat:@"Could not create %@", path]);
    }
    return NO;
  }
  BOOL json = [self isJSONPath:path];
  if (json) {
    fputs("[\r\n", file);
  } else {
    fputs("\"Hash Prefix\",\"Name\",\"Logical Size\",\"Physical Size\",\"Last Change\",\"Attributes\",\"Sampled hash\"\r\n", file);
  }
  BOOL first = YES;
  for (NSArray *row in rows) {
    LDDuplicateGroup *group = [row objectAtIndex:0];
    LDFileNode *node = [row objectAtIndex:1];
    time_t seconds = (time_t)[node modificationTime];
    struct tm utc;
    memset(&utc, 0, sizeof(utc));
    gmtime_r(&seconds, &utc);
    char lastChange[32];
    snprintf(lastChange, sizeof(lastChange), "%04d-%02d-%02dT%02d:%02d:%02dZ",
             utc.tm_year + 1900, utc.tm_mon + 1, utc.tm_mday, utc.tm_hour, utc.tm_min, utc.tm_sec);
    NSString *attributes = [LDFileAttributes attributeStringForNode:node];
    if (json) {
      // SaveDuplicatesJson (v2.9.3 CsvLoader.cpp:628-647): the CSV's
      // columns, "Sampled hash" unquoted.
      fputs(first ? "{\r\n" : ",\r\n{\r\n", file);
      LDWriteJSONKey(file, @"Hash Prefix", YES);
      LDWriteJSONQuotedString(file, [group hashString]);
      LDWriteJSONKey(file, @"Name", NO);
      LDWriteJSONQuotedString(file, [row objectAtIndex:2]);
      LDWriteJSONKey(file, @"Logical Size", NO);
      fprintf(file, "%llu", [node size]);
      LDWriteJSONKey(file, @"Physical Size", NO);
      fprintf(file, "%llu", [node allocatedSize]);
      LDWriteJSONKey(file, @"Last Change", NO);
      fprintf(file, "\"%s\"", lastChange);
      LDWriteJSONKey(file, @"Attributes", NO);
      LDWriteJSONQuotedString(file, attributes);
      LDWriteJSONKey(file, @"Sampled hash", NO);
      fputs("false\r\n}", file);
    } else {
      LDWriteQuotedString(file, [group hashString]);
      fputc(',', file);
      LDWriteQuotedString(file, [row objectAtIndex:2]);
      fprintf(file, ",%llu,%llu,%s,", [node size], [node allocatedSize], lastChange);
      LDWriteQuotedString(file, attributes);
      // WinDirStat 2.9 hashes very large files from samples when asked to;
      // LinDirStat always hashes whole files.
      fputs(",false\r\n", file);
    }
    first = NO;
  }
  if (json) {
    fputs(first ? "]\r\n" : "\r\n]\r\n", file);
  }
  BOOL failed = ferror(file) != 0;
  if (fclose(file) != 0) {
    failed = YES;
  }
  if (failed && error) {
    *error = LDCSVPOSIXError(errno ? errno : EIO, [NSString stringWithFormat:@"Could not write %@", path]);
  }
  return !failed;
}

+ (LDFileNode *)readTreeFromPath:(NSString *)path error:(NSError **)error
{
  return [self readTreeFromPath:path processHardLinks:YES error:error];
}

+ (LDFileNode *)readTreeFromPath:(NSString *)path processHardLinks:(BOOL)processHardLinks error:(NSError **)error
{
  NSError *readError = nil;
  NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&readError];
  if (!data) {
    if (error) {
      int code = [[readError domain] isEqualToString:NSPOSIXErrorDomain] ? (int)[readError code] : ENOENT;
      *error = LDCSVPOSIXError(code, [NSString stringWithFormat:@"Could not read %@", path]);
    }
    return nil;
  }

  LDCSVParser parser;
  parser.bytes = [data bytes];
  parser.length = [data length];
  parser.position = 0;
  parser.storage = [NSMutableData data];
  parser.fields = [NSMutableData data];
  parser.json = [self isJSONPath:path];
  parser.headerRead = NO;
  if (parser.length >= 3 && memcmp(parser.bytes, "\xEF\xBB\xBF", 3) == 0) {
    parser.position = 3;
  }

  NSError *failure = nil;
  LDFileNode *root = nil;
  @autoreleasepool {
    root = [self readTreeWithParser:&parser processHardLinks:processHardLinks error:&failure];
  }
  if (!root && error) {
    *error = failure;
  }
  return root;
}

+ (LDFileNode *)readTreeWithParser:(LDCSVParser *)parser processHardLinks:(BOOL)processHardLinks error:(NSError **)error
{
  // Header: columns are matched by name, in any order.
  int status = LDParserNextRecord(parser);
  if (status <= 0) {
    *error = LDCSVError(status < 0 ? LDCSVErrorMalformed : LDCSVErrorNoRows,
                        status < 0 ? @"The header has an unterminated quote."
                                   : (parser->json ? @"The file has no JSON array." : @"The file is empty."));
    return nil;
  }
  NSUInteger columnIndex[LDCSVColumnCount];
  NSUInteger column = 0;
  for (column = 0; column < LDCSVColumnCount; column++) {
    columnIndex[column] = NSNotFound;
  }
  NSUInteger headerCount = LDParserFieldCount(parser);
  NSUInteger field = 0;
  for (field = 0; field < headerCount; field++) {
    size_t length = 0;
    const char *bytes = LDParserField(parser, field, &length);
    NSString *name = LDStringFromBytes(bytes, length);
    for (column = 0; column < LDCSVColumnCount; column++) {
      if ([name isEqualToString:LDCSVColumnNames[column]]) {
        columnIndex[column] = field;
      }
    }
  }
  NSUInteger neededFields = 0;
  for (column = 0; column < LDCSVColumnOwner; column++) {
    if (columnIndex[column] == NSNotFound) {
      *error = LDCSVError(LDCSVErrorMissingColumn,
                          [NSString stringWithFormat:@"The column \"%@\" is missing.", LDCSVColumnNames[column]]);
      return nil;
    }
    neededFields = MAX(neededFields, columnIndex[column] + 1);
  }

  LDFileNode *root = nil;
  char separator = '/';
  NSMutableDictionary *parents = [NSMutableDictionary dictionary];
  LDNameArena *arena = [[LDNameArena alloc] init];
  // Files that share an Index are links to one file: counted once, as when
  // scanning. Files written without an Index (0) are taken as they are.
  LDHardLinkTable *hardLinks = [[LDHardLinkTable alloc] init];
  [hardLinks setShowsHardLinks:processHardLinks];
  [hardLinks setMatchesInodesOnly:YES];
  NSUInteger row = 1;

  while ((status = LDParserNextRecord(parser)) > 0) {
    row++;
    if (LDParserFieldCount(parser) < neededFields) {
      *error = LDCSVError(LDCSVErrorMalformed,
                          [NSString stringWithFormat:@"%@ has %lu fields; %lu are needed.", LDRowDescription(row),
                                                     (unsigned long)LDParserFieldCount(parser), (unsigned long)neededFields]);
      return nil;
    }

    size_t nameLength = 0;
    const char *name = LDParserField(parser, columnIndex[LDCSVColumnName], &nameLength);
    unsigned long long type = strtoull(LDParserField(parser, columnIndex[LDCSVColumnWinDirStatAttributes], NULL), NULL, 16);
    unsigned long long logical = strtoull(LDParserField(parser, columnIndex[LDCSVColumnLogicalSize], NULL), NULL, 10);
    unsigned long long physical = strtoull(LDParserField(parser, columnIndex[LDCSVColumnPhysicalSize], NULL), NULL, 10);
    size_t timeLength = 0;
    const char *timeText = LDParserField(parser, columnIndex[LDCSVColumnLastChange], &timeLength);
    int64_t modificationTime = LDParseTime(timeText, timeLength);
    const char *attributes = LDParserField(parser, columnIndex[LDCSVColumnAttributes], NULL);
    unsigned long long index = strtoull(LDParserField(parser, columnIndex[LDCSVColumnIndex], NULL), NULL, 16);

    BOOL isDirectory = (type & (LDCSVTypeMyComputer | LDCSVTypeDrive | LDCSVTypeDirectory)) != 0;
    LDFileNodeKind kind = isDirectory ? LDFileNodeKindDirectory : LDFileNodeKindFile;
    if (type & LDCSVTypeFreeSpace) {
      kind = LDFileNodeKindFreeSpace;
    } else if (type & LDCSVTypeUnknown) {
      kind = LDFileNodeKindUnknown;
    }
    // Folders' sizes come from their children.
    unsigned long long ownLogical = isDirectory ? 0 : logical;
    unsigned long long ownPhysical = isDirectory ? 0 : physical;

    LDFileNode *node = nil;
    if (!root) {
      // The first row is the root (WinDirStat's Root bit); it keeps its
      // full path. A Windows root ("C:\") switches the separator.
      if (memchr(name, '\\', nameLength) && !memchr(name, '/', nameLength)) {
        separator = '\\';
      }
      if (type & LDCSVTypeMyComputer) {
        node = [LDComputerNode computerNode];
      } else {
        node = [LDFileNode nodeWithPath:LDStringFromBytes(name, nameLength) kind:kind size:0];
        [node setSize:ownLogical allocatedSize:ownPhysical];
        [node setUsesBackslashPaths:separator == '\\'];
      }
      root = node;
    } else {
      if (type & LDCSVTypeRoot) {
        *error = LDCSVError(LDCSVErrorMalformed, [NSString stringWithFormat:@"%@ is a second root.", LDRowDescription(row)]);
        return nil;
      }
      LDFileNode *parent = nil;
      const char *leaf = name;
      size_t leafLength = nameLength;
      if ((type & LDCSVTypeDrive) && [root kind] == LDFileNodeKindDirectory) {
        // Drives below WinDirStat's "This PC" root keep their full path.
        parent = root;
      } else {
        const char *slash = NULL;
        size_t i = nameLength;
        while (i > 0) {
          if (name[i - 1] == separator) {
            slash = name + i - 1;
            break;
          }
          i--;
        }
        if (slash) {
          parent = [parents objectForKey:[NSData dataWithBytesNoCopy:(void *)name length:(NSUInteger)(slash - name) freeWhenDone:NO]];
          leaf = slash + 1;
          leafLength = nameLength - (size_t)(leaf - name);
        }
        if (!parent || leafLength == 0) {
          *error = LDCSVError(LDCSVErrorMissingParent,
                              [NSString stringWithFormat:@"%@: no folder row precedes \"%@\".", LDRowDescription(row),
                                                         LDStringFromBytes(name, nameLength)]);
          return nil;
        }
      }
      if (parent == root && [root isComputer]) {
        // A root of a LinDirStat multi-root scan keeps its full path. Below
        // WinDirStat's "This PC" the drives ("C:\") switch the separator.
        if (memchr(name, '\\', nameLength) && !memchr(name, '/', nameLength)) {
          separator = '\\';
        }
        node = [LDFileNode nodeWithPath:LDStringFromBytes(name, nameLength) kind:kind size:0];
        [node setSize:ownLogical allocatedSize:ownPhysical];
        [node setUsesBackslashPaths:separator == '\\'];
      } else {
        node = [LDFileNode nodeWithNameBytes:leaf length:leafLength arena:arena kind:kind size:ownLogical allocatedSize:ownPhysical];
      }
      [parent addChild:node];
    }

    [node setModificationTime:(NSTimeInterval)modificationTime];
    [node setMode:LDModeForRow(isDirectory, attributes)];
    if (!isDirectory && index != 0) {
      [hardLinks addLink:node device:0 inode:index size:ownLogical allocatedSize:ownPhysical ignoringLinksUnder:nil];
    }
    if (isDirectory) {
      LDRegisterParent(parents, node, name, nameLength, separator);
    }
  }

  if (status < 0) {
    NSString *description = parser->json
      ? [NSString stringWithFormat:@"The file is not valid JSON after item %lu.", (unsigned long)(row - 1)]
      : [NSString stringWithFormat:@"%@ has an unterminated quote.", LDRowDescription(row + 1)];
    *error = LDCSVError(LDCSVErrorMalformed, description);
    return nil;
  }
  if (!root) {
    *error = LDCSVError(LDCSVErrorNoRows, parser->json ? @"The JSON array has no items." : @"The file has a header but no rows.");
    return nil;
  }

  if ([root isKindOfClass:[LDDirectoryNode class]]) {
    [(LDDirectoryNode *)root setOwnedStorage:@[arena, hardLinks]];
    [LDHardLinks updateTree:root table:hardLinks metric:LDSizeMetricPhysical retiring:nil];
  }
  [root recalculateAggregateSize];
  [root sortChildrenByMetric:LDSizeMetricPhysical];
  return root;
}

@end
