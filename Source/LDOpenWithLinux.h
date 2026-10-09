#import "LDOpenWith.h"

#if !defined(__APPLE__)

@class LDMimeApps;
@class LDFileTypeDescriptions;

// The Linux backend's parts, for tests: its own application database and
// MIME type lookup instead of the user's.
@interface LDOpenWith (Linux)
- (id)initWithMimeApps:(LDMimeApps *)mimeApps typeDescriptions:(LDFileTypeDescriptions *)typeDescriptions;
// inode/directory for folders; otherwise by extension, then text/plain for
// files that look like UTF-8 text, else application/octet-stream.
- (NSString *)mimeTypeForPath:(NSData *)path;
@end

#endif
