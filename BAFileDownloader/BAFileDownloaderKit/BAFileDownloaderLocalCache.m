//
//  BAFileDownloaderLocalCache.m
//  BAFileDownloader
//
//  Created by nds on 2017/12/1.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "BAFileDownloaderLocalCache.h"
#import "NSString+BAFileDownloaderCategory.h"
#import <CoreGraphics/CoreGraphics.h>
#import "BAStreamFileMerger.h"
#import "NSError+BAFileDownloaderCategory.h"

typedef NS_ENUM(NSUInteger, BAFileLocalCacheSliceState) {
    BAFileLocalCacheSliceStateNull = 0,
    BAFileLocalCacheSliceStateError,
    BAFileLocalCacheSliceStateSuccessed,
};

static NSString *const BAFileLocalCacheRootPath = @"BAFileLocalCache/";
static NSString *const BAFileLocalCacheTmpFilePoolPath = @"tmpFilePool/";
static NSString *const BAFileLocalCacheSlicesPoolPath = @"slicesPool/";
static NSString *const BAFileLocalCacheInfoFileName = @"cacheInfo.plist";

static NSString *const BAFileLocalCacheInfoKeyState = @"state";
static NSString *const BAFileLocalCacheInfoKeyFileMD5 = @"file_MD5";
static NSString *const BAFileLocalCacheInfoKeySlicesRecord = @"slices_record";
static NSString *const BAFileLocalCacheInfoKeyFullDataPath = @"full_data_path";

@interface BAFileDownloaderLocalCacheInfo : NSObject

@property (nonatomic) BAFileDownloaderLocalCacheState state;
@property (nonatomic) NSString *fileMD5;
@property (nonatomic) NSMutableDictionary *slicesRecord;//key: range(e.g: 0-100), value: slice data file path
@property (nonatomic) NSString *fullDataPath;

@end

@implementation BAFileDownloaderLocalCacheInfo

- (instancetype)init
{
    self = [super init];
    if (self) {
        _state = BAFileDownloaderLocalCacheStateNull;
        _slicesRecord = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dic
{
    self = [self init];
    if (self && dic) {
        NSArray *allKeys = [dic allKeys];
        if ([allKeys containsObject:BAFileLocalCacheInfoKeyState]) {
            _state = ((NSNumber *)[dic objectForKey:BAFileLocalCacheInfoKeyState]).integerValue;
        }
        if ([allKeys containsObject:BAFileLocalCacheInfoKeyFileMD5]) {
            _fileMD5 = (NSString *)[dic objectForKey:BAFileLocalCacheInfoKeyFileMD5];
        }
        if ([allKeys containsObject:BAFileLocalCacheInfoKeySlicesRecord]) {
            _slicesRecord = [NSMutableDictionary dictionaryWithDictionary:[dic objectForKey:BAFileLocalCacheInfoKeySlicesRecord]];
        }
        if ([allKeys containsObject:BAFileLocalCacheInfoKeyFullDataPath]) {
            _fullDataPath = [dic objectForKey:BAFileLocalCacheInfoKeyFullDataPath];
        }
    }
    return self;
}

- (NSDictionary *)toDictionary
{
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    [result setObject:@(_state) forKey:BAFileLocalCacheInfoKeyState];
    if (_fileMD5) {
        [result setObject:_fileMD5 forKey:BAFileLocalCacheInfoKeyFileMD5];
    }
    if (_slicesRecord) {
        [result setObject:_slicesRecord forKey:BAFileLocalCacheInfoKeySlicesRecord];
    }
    if (_fullDataPath) {
        [result setObject:_fullDataPath forKey:BAFileLocalCacheInfoKeyFullDataPath];
    }
    return result;
}

@end

@interface BAFileDownloaderLocalCache()

@property (nonatomic) NSString *URL;
@property (nonatomic) NSOperationQueue *queue;
@property (nonatomic) BAFileDownloaderLocalCacheInfo *tmpCacheInfo;

@end

@implementation BAFileDownloaderLocalCache

- (instancetype)initWithURL:(NSString *)URL
{
    self = [self init];
    if (self && [URL BAFD_isValid]) {
        _URL = URL;
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 1;
        _queue.name = [NSString stringWithFormat:@"BAFileDownloaderLocalCacheQueue_%@", [_URL BAFD_MD5]];
        [self createDirectoryAtPath:[self cacheFolderPath]];
        [self createDirectoryAtPath:[self slicesPoolPath]];
        [self createDirectoryAtPath:[self tmpFilePoolPath]];
    }
    return self;
}

#pragma mark - public method

- (BAFileDownloaderLocalCacheState)state
{
    return [self cacheInfo].state;
}

- (void)updateSlicesSheet:(NSInteger)fullDataLength sliceSize:(NSInteger)sliceSize finishedBlock:(void(^)(NSError *error))finishedBlock
{
    __weak typeof(self) weakSelf = self;
    [self.queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSMutableDictionary *newSlicesRecord = [[NSMutableDictionary alloc] init];
        NSInteger sliceCount = ceil((CGFloat)fullDataLength / (CGFloat)sliceSize);
        for (NSInteger i=0; i<sliceCount; i++) {
            NSInteger location = sliceSize * i;
            NSInteger destination = sliceSize * (i + 1);
            if (destination > fullDataLength) {
                destination = fullDataLength;
            }
            [newSlicesRecord setObject:@(BAFileLocalCacheSliceStateNull) forKey:NSStringFromRange(NSMakeRange(location, destination - location))];
        }
        BAFileDownloaderLocalCacheInfo *cacheInfo = [strongSelf cacheInfo];
        if (!cacheInfo) {
            cacheInfo = [[BAFileDownloaderLocalCacheInfo alloc] init];
        }
        cacheInfo.slicesRecord = newSlicesRecord;
        [strongSelf updateCacheInfo:cacheInfo];
        if (finishedBlock) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){
                finishedBlock(nil);
            });
        }
    }];
}

- (void)getUncachedSliceRanges:(void(^)(NSArray *sliceRanges))finishedBlock
{
    __weak typeof(self) weakSelf = self;
    [self.queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSMutableArray *result = nil;
        BAFileDownloaderLocalCacheInfo *cacheInfo = [strongSelf cacheInfo];
        for (NSString *rangeString in [cacheInfo.slicesRecord allKeys]) {
            BAFileLocalCacheSliceState state = ((NSNumber *)[cacheInfo.slicesRecord objectForKey:rangeString]).integerValue;
            if (BAFileLocalCacheSliceStateNull == state || BAFileLocalCacheSliceStateError == state) {
                if (!result) {
                    result = [[NSMutableArray alloc] init];
                }
                [result addObject:rangeString];
            }
        }
        if (finishedBlock) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){
                finishedBlock(result);
            });
        }
    }];
}

- (void)getFailedSliceRanges:(void(^)(NSArray *sliceRanges))finishedBlock
{
    __weak typeof(self) weakSelf = self;
    [self.queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSMutableArray *result = nil;
        BAFileDownloaderLocalCacheInfo *cacheInfo = [strongSelf cacheInfo];
        for (NSString *rangeString in [cacheInfo.slicesRecord allKeys]) {
            if (BAFileLocalCacheSliceStateError == ((NSNumber *)[cacheInfo.slicesRecord objectForKey:rangeString]).integerValue) {
                if (!result) {
                    result = [[NSMutableArray alloc] init];
                }
                [result addObject:rangeString];
            }
        }
        if (finishedBlock) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){
                finishedBlock(result);
            });
        }
    }];
}

- (void)saveSliceData:(NSString *)dataPath error:(NSError *)error sliceRange:(NSRange)sliceRange finishedBlock:(void(^)(NSError *error))finishedBlock
{
    //1.copy tmp file from NSURLSession path to sand box path synchronized, in case tmp file deleted
    NSString *rangeString = NSStringFromRange(sliceRange);
    NSString *tmpFilePath = [self tmpSliceFilePathWithSliceFlag:rangeString];
    if (!error) {
        [self copyFileFrom:dataPath to:tmpFilePath overWrite:YES];
    }
    __weak typeof(self) weakSelf = self;
    [self.queue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        
        void(^finishedActionBlock)(NSError *) = ^(NSError *error){
            if (finishedBlock) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){
                    finishedBlock(error);
                });
            }
        };
        
        //2.start save action
        if (error) {
            BAFileDownloaderLocalCacheInfo *cacheInfo = [strongSelf cacheInfo];
            [cacheInfo.slicesRecord setObject:@(BAFileLocalCacheSliceStateError) forKey:NSStringFromRange(sliceRange)];
            [strongSelf updateCacheInfo:cacheInfo];
            finishedActionBlock(error);
        } else {
            if ([strongSelf isPathExist:tmpFilePath]) {
                //3.copy slice data file from sand box path to given path
                NSString *slicePath = [strongSelf cachedSliceDataPathWithSliceFlag:rangeString];
                [strongSelf moveFileFrom:tmpFilePath to:slicePath overWrite:YES];
                BAFileDownloaderLocalCacheInfo *cacheInfo = [strongSelf cacheInfo];
                [cacheInfo.slicesRecord setObject:@(BAFileLocalCacheSliceStateSuccessed) forKey:rangeString];
                
                NSArray *allValues = [cacheInfo.slicesRecord allValues];
                BAFileDownloaderLocalCacheState tmpState = ([allValues containsObject:@(BAFileLocalCacheSliceStateNull)] || [allValues containsObject:@(BAFileLocalCacheSliceStateError)]) ? BAFileDownloaderLocalCacheStatePart : BAFileDownloaderLocalCacheStateFull;
                if (tmpState == BAFileDownloaderLocalCacheStateFull) {
                    __weak typeof(strongSelf) weakSelf2 = strongSelf;
                    //4.merge all slices if all of it saved
                    [strongSelf mergeAllSlicesDataWithFinishedBlock:^(NSError *mergeActionError){
                        __strong typeof(weakSelf2) strongSelf2 = weakSelf2;
                        if (!mergeActionError) {
                            //5.update cache info
                            cacheInfo.state = BAFileDownloaderLocalCacheStateFull;
                            [strongSelf2 updateCacheInfo:cacheInfo];
                            [strongSelf2 removeFilesAtPath:[strongSelf2 slicesPoolPath]];
                            [strongSelf2 createDirectoryAtPath:[strongSelf2 slicesPoolPath]];
                        }
                        //6.call finished action block
                        finishedActionBlock(mergeActionError);
                    }];
                } else {
                    cacheInfo.state = tmpState;
                    [strongSelf updateCacheInfo:cacheInfo];
                    finishedActionBlock(nil);
                }
            } else {
                finishedActionBlock([NSError BAFD_simpleErrorWithDescription:@"slice file invalid"]);
            }
        }
    }];
}

- (NSString *)fullDataPath
{
    return [self cacheInfo].state == BAFileDownloaderLocalCacheStateFull ? [self cachedFullDataPath] : nil;
}

- (void)cleanCache
{
    
}

#pragma mark - private method
#pragma mark cache info method
- (BAFileDownloaderLocalCacheInfo *)cacheInfo
{
    if (![self.URL BAFD_isValid]) {
        return nil;
    }
    if (self.tmpCacheInfo) {
        return self.tmpCacheInfo;
    }
    NSString *folderPath = [self cacheFolderPath];
    NSString *cacheInfoPath = [self cacheInfoPath];
    if ([self isPathExist:cacheInfoPath]) {
        NSDictionary *dic = [NSDictionary dictionaryWithContentsOfFile:cacheInfoPath];
        if (dic) {
            self.tmpCacheInfo = [[BAFileDownloaderLocalCacheInfo alloc] initWithDictionary:dic];
            return self.tmpCacheInfo;
        } else {
            [self removeFilesAtPath:folderPath];
            [self createDirectoryAtPath:folderPath];
            return nil;
        }
    } else {
        [self createDirectoryAtPath:folderPath];
        return nil;
    }
}

- (void)updateCacheInfo:(BAFileDownloaderLocalCacheInfo *)newInfo
{
    if (![self.URL BAFD_isValid]) {
        return;
    }
    [[newInfo toDictionary] writeToFile:[self cacheInfoPath] atomically:YES];
    self.tmpCacheInfo = newInfo;
}

#pragma mark file method
- (void)createDirectoryAtPath:(NSString *)path
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory;
    BOOL existed =  [fileManager fileExistsAtPath:path isDirectory:&isDirectory];
    if (existed && isDirectory) {
        return;
    }
    [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)removeFilesAtPath:(NSString *)path
{
    if ([self isPathExist:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

- (BOOL)isPathExist:(NSString *)path
{
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (void)copyFileFrom:(NSString *)fromPath to:(NSString *)toPath overWrite:(BOOL)overWrite;
{
    if (![fromPath BAFD_isValid] || ![toPath BAFD_isValid]) {
        return;
    }
    if (![self isPathExist:fromPath]) {
        return;
    }
    if ([self isPathExist:toPath]) {
        if (overWrite) {
            [self removeFilesAtPath:toPath];
        } else {
            return;
        }
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager copyItemAtPath:fromPath toPath:toPath error:nil];
}

- (void)moveFileFrom:(NSString *)fromPath to:(NSString *)toPath overWrite:(BOOL)overWrite
{
    [self copyFileFrom:fromPath to:toPath overWrite:overWrite];
    [self removeFilesAtPath:fromPath];
}

#pragma mark path method
- (NSString *)rootPathOfCache
{
    return [NSString stringWithFormat:@"%@/%@", NSHomeDirectory(), BAFileLocalCacheRootPath];
}

- (NSString *)cacheFolderPath
{
    if (![self.URL BAFD_isValid]) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@%@/", [self rootPathOfCache], [self.URL BAFD_MD5]];
}

- (NSString *)slicesPoolPath
{
    if (![self.URL BAFD_isValid]) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@%@/%@", [self rootPathOfCache], [self.URL BAFD_MD5], BAFileLocalCacheSlicesPoolPath];
}

- (NSString *)tmpFilePoolPath
{
    if (![self.URL BAFD_isValid]) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@%@/%@", [self rootPathOfCache], [self.URL BAFD_MD5], BAFileLocalCacheTmpFilePoolPath];
}

- (NSString *)cacheInfoPath
{
    if (![self.URL BAFD_isValid]) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@%@/%@", [self rootPathOfCache], [self.URL BAFD_MD5], BAFileLocalCacheInfoFileName];
}

- (NSString *)cachedFullDataPath
{
    if (![self.URL BAFD_isValid]) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@%@/fullData", [self rootPathOfCache], [self.URL BAFD_MD5]];
}

- (NSString *)tmpSliceFilePathWithSliceFlag:(NSString *)sliceFlag
{
    if (![self.URL BAFD_isValid]) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@%@/%@%@", [self rootPathOfCache], [self.URL BAFD_MD5], BAFileLocalCacheTmpFilePoolPath, sliceFlag];
}

- (NSString *)cachedSliceDataPathWithSliceFlag:(NSString *)sliceFlag
{
    if (![self.URL BAFD_isValid]) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@%@/%@%@", [self rootPathOfCache], [self.URL BAFD_MD5], BAFileLocalCacheSlicesPoolPath, sliceFlag];
}

#pragma mark slice method
- (void)mergeAllSlicesDataWithFinishedBlock:(void(^)(NSError *error))finishedBlock
{
    BAFileDownloaderLocalCacheInfo *cacheInfo = [self cacheInfo];
    if (!cacheInfo) {
        if (finishedBlock) {
            finishedBlock([NSError BAFD_simpleErrorWithDescription:@"cache is null"]);
        }
        return;
    }
    NSMutableArray *allSlices = cacheInfo.slicesRecord.allKeys.mutableCopy;
    [allSlices sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        if ([obj1 isKindOfClass:[NSString class]] && [obj2 isKindOfClass:[NSString class]]) {
            NSRange range1 = NSRangeFromString(obj1);
            NSRange range2 = NSRangeFromString(obj2);
            if (range1.location != NSNotFound && range2.location != NSNotFound) {
                return (range1.location < range2.location) ? NSOrderedAscending : NSOrderedDescending;
            } else {
                return NSOrderedAscending;
            }
        } else {
            return NSOrderedAscending;
        }
    }];
    for (NSInteger i=0; i<allSlices.count; i++) {
        [allSlices replaceObjectAtIndex:i withObject:[self cachedSliceDataPathWithSliceFlag:[allSlices objectAtIndex:i]]];
    }
    [BAStreamFileMerger mergeFiles:allSlices into:[self cachedFullDataPath] finishedBlock:^(NSError *error) {
        if (finishedBlock) {
            finishedBlock(error);
        }
    }];
}

@end
