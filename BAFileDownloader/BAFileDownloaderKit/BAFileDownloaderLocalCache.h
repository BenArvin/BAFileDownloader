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

@interface BAFileDownloaderLocalCache : NSObject

- (instancetype)initWithURL:(NSString *)URL;

- (BAFileDownloaderLocalCacheState)state;
- (void)updateSlicesSheet:(NSInteger)fullDataLength sliceSize:(NSInteger)sliceSize finishedBlock:(void(^)(NSError *error))finishedBlock;

- (void)getUncachedSliceRanges:(void(^)(NSArray *sliceRanges))finishedBlock;
- (void)getFailedSliceRanges:(void(^)(NSArray *sliceRanges))finishedBlock;
- (void)saveSliceData:(NSString *)dataPath error:(NSError *)error sliceRange:(NSRange)sliceRange finishedBlock:(void(^)(NSError *error))finishedBlock;

- (NSString *)fullDataPath;

- (void)cleanCache;

@end
