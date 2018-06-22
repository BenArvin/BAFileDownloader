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

static NSString *const BAFileLocalCacheRootPath = @"Library/Caches/BAFileDownloader/";
static NSString *const BAFileLocalCacheTmpFilePoolPath = @"tmpFilePool/";
static NSString *const BAFileLocalCacheSlicesPoolPath = @"slicesPool/";
static NSString *const BAFileLocalCacheInfoFileName = @"cacheInfo.plist";

static NSString *const BAFileLocalCacheInfoKeyState = @"state";
static NSString *const BAFileLocalCacheInfoKeyFileMD5 = @"file_MD5";
static NSString *const BAFileLocalCacheInfoKeySlicesRecord = @"slices_record";
static NSString *const BAFileLocalCacheInfoKeyFullDataPath = @"full_data_path";
static NSString *const BAFileLocalCacheInfoKeyFullDataLength = @"full_data_length";

@interface BAFileDownloaderLocalCacheInfo : NSObject

@property (nonatomic) BAFileDownloaderLocalCacheState state;
@property (nonatomic) NSString *fileMD5;
@property (nonatomic) NSMutableDictionary *slicesRecord;//key: range(e.g: 0-100), value: slice data file path
@property (nonatomic) NSString *fullDataPath;
@property (nonatomic) NSUInteger fullDataLength;

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
        if ([allKeys containsObject:BAFileLocalCacheInfoKeyFullDataLength]) {
            _fullDataLength = ((NSNumber *)[dic objectForKey:BAFileLocalCacheInfoKeyFullDataLength]).integerValue;
        }
    }
    return self;
}

- (NSDictionary *)toDictionary
{
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    [result setObject:@(_state) forKey:BAFileLocalCacheInfoKeyState];
    [result setObject:@(_fullDataLength) forKey:BAFileLocalCacheInfoKeyFullDataLength];
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
@property (nonatomic) BAFileDownloaderLocalCacheInfo *tmpCacheInfo;

@end

@implementation BAFileDownloaderLocalCache

- (instancetype)initWithURL:(NSString *)URL
{
    self = [self init];
    if (self && [URL BAFD_isValid]) {
        _URL = URL;
        [self createDirectoryAtPath:[self cacheFolderPath]];
        [self createDirectoryAtPath:[self slicesPoolPath]];
        [self createDirectoryAtPath:[self tmpFilePoolPath]];
        
        [self skipiCloudBackup:[self rootPathOfCache]];
    }
    return self;
}

#pragma mark - public method

- (BAFileDownloaderLocalCacheState)state
{
    return [self cacheInfo].state;
}

- (NSError *)updateSlicesSheet:(NSInteger)fullDataLength sliceSize:(NSInteger)sliceSize
{
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
    BAFileDownloaderLocalCacheInfo *cacheInfo = [self cacheInfo];
    if (!cacheInfo) {
        cacheInfo = [[BAFileDownloaderLocalCacheInfo alloc] init];
    }
    cacheInfo.fullDataLength = fullDataLength;
    cacheInfo.slicesRecord = newSlicesRecord;
    [self updateCacheInfo:cacheInfo];
    return nil;
}

- (NSUInteger)getFullDataLength
{
    return [self cacheInfo].fullDataLength;
}

- (NSUInteger)getCachedSliceLength
{
    NSUInteger result = 0;
    BAFileDownloaderLocalCacheInfo *cacheInfo = [self cacheInfo];
    for (NSString *rangeString in [cacheInfo.slicesRecord allKeys]) {
        BAFileLocalCacheSliceState state = ((NSNumber *)[cacheInfo.slicesRecord objectForKey:rangeString]).integerValue;
        if (BAFileLocalCacheSliceStateSuccessed == state) {
            NSRange range = NSRangeFromString(rangeString);
            result = result + range.length;
        }
    }
    return result;
}

- (NSArray *)getUncachedSliceRanges
{
    NSMutableArray *result = nil;
    BAFileDownloaderLocalCacheInfo *cacheInfo = [self cacheInfo];
    for (NSString *rangeString in [cacheInfo.slicesRecord allKeys]) {
        BAFileLocalCacheSliceState state = ((NSNumber *)[cacheInfo.slicesRecord objectForKey:rangeString]).integerValue;
        if (BAFileLocalCacheSliceStateNull == state || BAFileLocalCacheSliceStateError == state) {
            if (!result) {
                result = [[NSMutableArray alloc] init];
            }
            [result addObject:rangeString];
        }
    }
    return result;
}

- (NSArray *)getFailedSliceRanges
{
    NSMutableArray *result = nil;
    BAFileDownloaderLocalCacheInfo *cacheInfo = [self cacheInfo];
    for (NSString *rangeString in [cacheInfo.slicesRecord allKeys]) {
        if (BAFileLocalCacheSliceStateError == ((NSNumber *)[cacheInfo.slicesRecord objectForKey:rangeString]).integerValue) {
            if (!result) {
                result = [[NSMutableArray alloc] init];
            }
            [result addObject:rangeString];
        }
    }
    return result;
}

- (NSString *)cacheNetResponseTmpSliceData:(NSString *)dataPath sliceRange:(NSRange)sliceRange
{
    if (![self isPathExist:dataPath]) {
        return nil;
    }
    NSString *rangeString = NSStringFromRange(sliceRange);
    NSString *tmpFilePath = [self tmpSliceFilePathWithSliceFlag:rangeString];
    [self copyFileFrom:dataPath to:tmpFilePath overWrite:YES];
    return tmpFilePath;
}

- (NSError *)saveSliceData:(NSString *)dataPath error:(NSError *)error sliceRange:(NSRange)sliceRange
{
    NSString *rangeString = NSStringFromRange(sliceRange);
    if (error) {
        BAFileDownloaderLocalCacheInfo *cacheInfo = [self cacheInfo];
        [cacheInfo.slicesRecord setObject:@(BAFileLocalCacheSliceStateError) forKey:NSStringFromRange(sliceRange)];
        [self updateCacheInfo:cacheInfo];
        return error;
    } else {
        if ([self isPathExist:dataPath]) {
            //3.copy slice data file from sand box path to given path
            NSString *slicePath = [self cachedSliceDataPathWithSliceFlag:rangeString];
            [self moveFileFrom:dataPath to:slicePath overWrite:YES];
            BAFileDownloaderLocalCacheInfo *cacheInfo = [self cacheInfo];
            [cacheInfo.slicesRecord setObject:@(BAFileLocalCacheSliceStateSuccessed) forKey:rangeString];
            
            NSArray *allValues = [cacheInfo.slicesRecord allValues];
            BAFileDownloaderLocalCacheState tmpState = ([allValues containsObject:@(BAFileLocalCacheSliceStateNull)] || [allValues containsObject:@(BAFileLocalCacheSliceStateError)]) ? BAFileDownloaderLocalCacheStatePart : BAFileDownloaderLocalCacheStateFull;
            if (tmpState == BAFileDownloaderLocalCacheStateFull) {
                //4.merge all slices if all of it saved
                __block NSError *tmpError = nil;
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                [self mergeAllSlicesDataWithFinishedBlock:^(NSError *mergeActionError){
                    tmpError = mergeActionError;
                    dispatch_semaphore_signal(semaphore);
                }];
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                
                //5.update cache info
                if (!tmpError) {
                    cacheInfo.state = BAFileDownloaderLocalCacheStateFull;
                    [self updateCacheInfo:cacheInfo];
                    [self removeFilesAtPath:[self slicesPoolPath]];
                    [self createDirectoryAtPath:[self slicesPoolPath]];
                }
                return tmpError;
            } else {
                cacheInfo.state = tmpState;
                [self updateCacheInfo:cacheInfo];
                return nil;
            }
        } else {
            return [NSError BAFD_simpleErrorWithDescription:@"slice file invalid"];
        }
    }
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

#pragma mark - icloud methods
- (NSError *)skipiCloudBackup:(NSString *)path
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return [NSError BAFD_simpleErrorWithDescription:@"path invalid"];
    }
    NSURL *URL = [NSURL fileURLWithPath:path];
    if (!URL) {
        return [NSError BAFD_simpleErrorWithDescription:@"path invalid"];
    }
    NSError *error = nil;
    BOOL success = [URL setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsExcludedFromBackupKey error:&error];
    if(!success || error){
        return error ? error : [NSError BAFD_simpleErrorWithDescription:@"failed"];
    } else {
        return nil;
    }
}

@end
