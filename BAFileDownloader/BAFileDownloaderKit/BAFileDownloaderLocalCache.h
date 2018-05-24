//
//  BAFileDownloaderLocalCache.h
//  BAFileDownloader
//
//  Created by nds on 2017/12/1.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, BAFileDownloaderLocalCacheState) {
    BAFileDownloaderLocalCacheStateNull = 0,
    BAFileDownloaderLocalCacheStatePart,
    BAFileDownloaderLocalCacheStateFull,
};


/**
 non-thread safe
 */
@interface BAFileDownloaderLocalCache : NSObject

- (instancetype)initWithURL:(NSString *)URL;

- (BAFileDownloaderLocalCacheState)state;
- (NSError *)updateSlicesSheet:(NSInteger)fullDataLength sliceSize:(NSInteger)sliceSize;

- (NSArray *)getUncachedSliceRanges;
- (NSArray *)getFailedSliceRanges;
- (NSString *)cacheNetResponseTmpSliceData:(NSString *)dataPath sliceRange:(NSRange)sliceRange;
- (NSError *)saveSliceData:(NSString *)dataPath error:(NSError *)error sliceRange:(NSRange)sliceRange;

- (NSString *)fullDataPath;

- (void)cleanCache;

@end
