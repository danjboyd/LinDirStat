#import <Foundation/Foundation.h>
#import "LDTreemapLayout.h"

// The little demo tree of WinDirStat's treemap preview on the Treemap
// options page (TreeMap.cpp CTreeMapPreview::BuildDemoData), for showing the
// treemap options without a scan.
@interface LDTreemapPreview : NSObject
{
  LDFileNode *_rootNode;
  NSDictionary *_colorIndexes;
}

+ (LDTreemapPreview *)sharedPreview;

// The demo tree, children sorted by descending size.
- (LDFileNode *)rootNode;
// Extension key -> palette index for the demo leaves.
- (NSDictionary *)colorIndexes;

// The demo tree rendered as width * height RGBA bytes, top row first.
- (NSData *)renderRGBAWithWidth:(int)width height:(int)height options:(LDTreemapOptions)options;
// The same with the theme's window and text colours, which an Auto grid
// colour is made from.
- (NSData *)renderRGBAWithWidth:(int)width height:(int)height options:(LDTreemapOptions)options
                     background:(LDRGBColor)background text:(LDRGBColor)text;

@end
