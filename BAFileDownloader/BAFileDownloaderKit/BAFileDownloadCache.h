//
//  BAFileDownloadCache.h
//  BAFileDownloader
//
//  Created by nds on 2017/12/1.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, BAFileDownloadCacheState) {
    BAFileDownloadCacheStateNull = 0,
    BAFileDownloadCacheStatePart,
    BAFileDownloadCacheStateFull,
};

/**
 non-thread safe
 */
@interface BAFileDownloadCache : NSObject

- (instancetype)initWithURL:(NSString *)URL;

- (BAFileDownloadCacheState)state;
- (NSError *)updateSlicesSheet:(NSInteger)fullDataLength sliceSize:(NSInteger)sliceSize;

- (NSUInteger)getFullDataLength;
- (NSString *)getFullDataMD5;
- (NSUInteger)getCachedSliceLength;
- (NSArray *)getUncachedSliceRanges;
- (NSArray *)getFailedSliceRanges;
- (NSString *)cacheNetResponseTmpSliceData:(NSString *)dataPath sliceRange:(NSRange)sliceRange;
- (NSError *)saveSliceData:(NSString *)dataPath error:(NSError *)error sliceRange:(NSRange)sliceRange;
- (NSError *)mergeAllSlicesData;

- (NSString *)fullDataPath;

- (void)cleanCache;

@end
