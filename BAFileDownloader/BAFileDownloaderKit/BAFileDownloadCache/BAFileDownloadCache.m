//
//  BAFileDownloadCache.m
//  BAFileDownloader
//
//  Created by nds on 2017/12/1.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "BAFileDownloadCache.h"
#import "NSString+BAFileDownloaderCategory.h"
#import <CoreGraphics/CoreGraphics.h>
#import "BAStreamFileMerger.h"
#import "NSError+BAFileDownloaderCategory.h"
#import "BAStreamFileMD5.h"
#import <sqlite3.h>

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

@interface BAFileDownloadCacheDBTaskInfo: NSObject

@property (nonatomic) NSString *taskKey;
@property (nonatomic) NSString *md5;
@property (nonatomic) NSUInteger fullLength;
@property (nonatomic) BAFileDownloadCacheState state;
@property (nonatomic) CGFloat startTime;
@property (nonatomic) CGFloat recentlyUsedTime;

@end

@implementation BAFileDownloadCacheDBTaskInfo

- (instancetype)init
{
    self = [super init];
    if (self) {
        _state = BAFileDownloadCacheStateNull;
        _fullLength = 0;
    }
    return self;
}

@end

@interface BAFileDownloadCacheDB: NSObject

@property (nonatomic) sqlite3 *database;

+ (BAFileDownloadCacheDB *)sharedDB;
- (BOOL)isTableExisted:(NSString *)tableName;

@end

@implementation BAFileDownloadCacheDB

- (void)dealloc
{
    if (self.database) {
        sqlite3_close(self.database);
    }
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self initalDatabase];
    }
    return self;
}

#pragma mark - public methods
+ (BAFileDownloadCacheDB *)sharedDB
{
    static dispatch_once_t onceToken;
    static BAFileDownloadCacheDB *_sharedDB;
    dispatch_once(&onceToken, ^{
        _sharedDB = [[BAFileDownloadCacheDB alloc] init];
    });
    return _sharedDB;
}

- (NSError *)updateSliceInfo:(NSString *)taskKey sliceKey:(NSString *)sliceKey state:(BAFileLocalCacheSliceState)state
{
    if (!taskKey || taskKey.length == 0 || !sliceKey || sliceKey.length == 0) {
        return [NSError BAFD_simpleErrorWithDescription:@"Update slice info error! Invalid params."];
    }
    NSString *tableName = [self buildSliceInfoTableName:taskKey];
    
    //1. create slice info table if need
    [self createTaskSliceInfoTable:taskKey];
    
    //2. check is row existed
    BOOL rowExisted = NO;
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(self.database, [[NSString stringWithFormat:@"SELECT * FROM %@ WHERE sliceKey='%@'", tableName, sliceKey] UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            rowExisted = YES;
            break;
        }
    }
    sqlite3_finalize(stmt);
    
    //3. insert or update row data
    if (rowExisted) {
        char *errMsg;
        if (sqlite3_exec(self.database, [[NSString stringWithFormat:@"UPDATE '%@' SET state=%ld WHERE sliceKey='%@'", tableName, state, sliceKey] UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
            return [NSError BAFD_simpleErrorWithDescription:[NSString stringWithUTF8String:errMsg]];
        }
    } else {
        char *errMsg;
        if (sqlite3_exec(self.database, [[NSString stringWithFormat:@"INSERT INTO '%@' VALUES('%@', %ld);", tableName, sliceKey, state] UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
            return [NSError BAFD_simpleErrorWithDescription:[NSString stringWithUTF8String:errMsg]];
        }
    }
    return nil;
}

- (NSError *)updateTaskStartTime
{
    return nil;
}

- (NSError *)updateTaskRecentlyUsedTime
{
    return nil;
}

- (NSError *)updateTaskInfo:(NSString *)taskKey md5:(NSString *)md5 fullLength:(NSInteger)fullLength state:(NSInteger)state
{
    if (!taskKey || taskKey.length == 0) {
        return [NSError BAFD_simpleErrorWithDescription:@"Update task info error! Invalid params."];
    }
    
    //1. create slice info table if need
    [self createTaskSliceInfoTable:taskKey];
    
    //2. check is row existed
    BOOL rowExisted = NO;
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(self.database, [[NSString stringWithFormat:@"SELECT * FROM tasks WHERE taskKey='%@'", taskKey] UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            rowExisted = YES;
        }
    }
    sqlite3_finalize(stmt);
    
    //3. insert or update row data
    if (rowExisted) {
        char *errMsg;
        if (sqlite3_exec(self.database, [[NSString stringWithFormat:@"UPDATE 'tasks' SET md5='%@', fullLength=%ld, state=%ld WHERE taskKey='%@'", md5, fullLength, state, taskKey] UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
            return [NSError BAFD_simpleErrorWithDescription:[NSString stringWithUTF8String:errMsg]];
        }
    } else {
        char *errMsg;
        if (sqlite3_exec(self.database, [[NSString stringWithFormat:@"INSERT INTO 'tasks' VALUES('%@', '%@', %ld, %ld);", taskKey, md5, fullLength, state] UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
            return [NSError BAFD_simpleErrorWithDescription:[NSString stringWithUTF8String:errMsg]];
        }
    }
    return nil;
}

- (NSError *)deleteRow:(NSString *)tableName rowKeyName:(NSString *)rowKeyName rowKeyValue:(NSString *)rowKeyValue
{
    if (!tableName || tableName.length == 0
        || !rowKeyName || rowKeyName.length == 0
        || !rowKeyValue || rowKeyValue.length == 0) {
        return [NSError BAFD_simpleErrorWithDescription:@"Delete row data error! Invalid params."];
    }
    char *errMsg;
    if (sqlite3_exec(self.database, [[NSString stringWithFormat:@"DELETE FROM '%@' WHERE %@=%@", tableName, rowKeyName, rowKeyValue] UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
        return [NSError BAFD_simpleErrorWithDescription:[NSString stringWithUTF8String:errMsg]];
    }
    return nil;
}

- (NSError *)deleteSliceInfoTable:(NSString *)taskKey
{
    if (!taskKey || taskKey.length == 0) {
        return [NSError BAFD_simpleErrorWithDescription:@"Delete table error! Invalid params."];
    }
    char *errMsg;
    if (sqlite3_exec(self.database, [[NSString stringWithFormat:@"DROP TABLE %@", [self buildSliceInfoTableName:taskKey]] UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
        return [NSError BAFD_simpleErrorWithDescription:[NSString stringWithUTF8String:errMsg]];
    }
    return nil;
}

- (BAFileDownloadCacheDBTaskInfo *)getTaskInfo:(NSString *)taskKey
{
    if (!taskKey || taskKey.length == 0) {
        return nil;
    }
    if (!self.database) {
        return nil;
    }
    BAFileDownloadCacheDBTaskInfo *result = nil;
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(self.database, [[NSString stringWithFormat:@"SELECT * FROM 'tasks' WHERE taskKey='%@'", taskKey] UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            if (!result) {
                result = [[BAFileDownloadCacheDBTaskInfo alloc] init];
            }
            const unsigned char *taskKey = sqlite3_column_text(stmt, 0);
            if (taskKey) {
                result.taskKey = [NSString stringWithUTF8String:(char *)taskKey];
            }
            const unsigned char *md5 = sqlite3_column_text(stmt, 1);
            if (md5) {
                result.md5 = [NSString stringWithUTF8String:(char *)md5];
            }
            result.fullLength = sqlite3_column_int(stmt, 2);
            result.state = sqlite3_column_int(stmt, 3);
            result.startTime = sqlite3_column_double(stmt, 4);
            result.recentlyUsedTime = sqlite3_column_double(stmt, 5);
            break;
        }
    }
    sqlite3_finalize(stmt);
    return result;
}

- (NSArray *)getAllSlicesKey:(NSString *)taskKey
{
    if (!taskKey || taskKey.length == 0) {
        return nil;
    }
    if (!self.database) {
        return nil;
    }
    NSMutableArray *result = nil;
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(self.database, [[NSString stringWithFormat:@"SELECT sliceKey FROM '%@'", [self buildSliceInfoTableName:taskKey]] UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *sliceKeyItem = sqlite3_column_text(stmt, 0);
            if (sliceKeyItem) {
                if (!result) {
                    result = [[NSMutableArray alloc] init];
                }
                [result addObject:[NSString stringWithUTF8String:(char *)sliceKeyItem]];
            }
        }
    }
    sqlite3_finalize(stmt);
    return result;
}

- (NSArray *)getSlicesKey:(NSString *)taskKey sliceState:(BAFileLocalCacheSliceState)state
{
    if (!taskKey || taskKey.length == 0) {
        return nil;
    }
    if (!self.database) {
        return nil;
    }
    NSMutableArray *result = nil;
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(self.database, [[NSString stringWithFormat:@"SELECT sliceKey FROM '%@' WHERE state=%ld", [self buildSliceInfoTableName:taskKey], state] UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *sliceKeyItem = sqlite3_column_text(stmt, 0);
            if (sliceKeyItem) {
                if (!result) {
                    result = [[NSMutableArray alloc] init];
                }
                [result addObject:[NSString stringWithUTF8String:(char *)sliceKeyItem]];
            }
        }
    }
    sqlite3_finalize(stmt);
    return result;
}

- (BAFileLocalCacheSliceState)getSliceState:(NSString *)taskKey sliceKey:(NSString *)sliceKey
{
    if (!taskKey || taskKey.length == 0 || !sliceKey || sliceKey.length == 0) {
        return BAFileLocalCacheSliceStateNull;
    }
    if (!self.database) {
        return BAFileLocalCacheSliceStateNull;
    }
    BAFileLocalCacheSliceState result = BAFileLocalCacheSliceStateNull;
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(self.database, [[NSString stringWithFormat:@"SELECT * FROM '%@' WHERE sliceKey='%@'", [self buildSliceInfoTableName:taskKey], sliceKey] UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            result = sqlite3_column_int(stmt, 2);
            break;
        }
    }
    sqlite3_finalize(stmt);
    return result;
}

#pragma mark - private methods
- (NSError *)initalDatabase
{
    NSError *errorForResult = nil;
    const char *dbpath = [[NSString stringWithFormat:@"%@/%@database.db", NSHomeDirectory(), BAFileLocalCacheRootPath] UTF8String];
    if (sqlite3_open(dbpath, &_database) == SQLITE_OK) {
        char *errMsg;
        if (sqlite3_exec(self.database, [[NSString stringWithFormat:@"create table if not exists tasks ('taskKey' text primary key, 'md5' text, 'fullLength' integer, 'state' integer default %ld)", BAFileDownloadCacheStateNull] UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
            errorForResult = [NSError BAFD_simpleErrorWithDescription:[NSString stringWithUTF8String:errMsg]];
        }
    } else {
        errorForResult = [NSError BAFD_simpleErrorWithDescription:@"Failed to open/create database"];
    }
    if (errorForResult && self.database) {
        sqlite3_close(self.database);
        self.database = nil;
    }
    return errorForResult;
}

- (NSString *)buildSliceInfoTableName:(NSString *)taskKey
{
    if (!taskKey || taskKey.length == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"sliceInfo_%@", taskKey];
}

- (BOOL)isTableExisted:(NSString *)tableName
{
    if (!tableName || tableName.length == 0) {
        return NO;
    }
    if (!self.database) {
        return NO;
    }
    BOOL result = NO;
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(self.database, [[NSString stringWithFormat:@"SELECT * FROM sqlite_master WHERE type='table' AND name='%@'", tableName] UTF8String], -1, &stmt, NULL) == SQLITE_OK) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            result = YES;
        }
    }
    sqlite3_finalize(stmt);
    return result;
}

- (NSError *)createTaskSliceInfoTable:(NSString *)taskKey
{
    if (!taskKey || taskKey.length == 0) {
        return [NSError BAFD_simpleErrorWithDescription:@"Create task slice info table error! Invalid params."];
    }
    if (!self.database) {
        return [NSError BAFD_simpleErrorWithDescription:@"Create task slice info table error! DB invalid!"];
    }
    char *errMsg;
    NSString *sqlCommand = [NSString stringWithFormat:@"create table if not exists %@ ('sliceKey' text primary key, 'state' integer default %ld)", [self buildSliceInfoTableName:taskKey], BAFileLocalCacheSliceStateNull];
    if (sqlite3_exec(self.database, [sqlCommand UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
        return [NSError BAFD_simpleErrorWithDescription:[NSString stringWithUTF8String:errMsg]];
    }
    return nil;
}

@end

@interface BAFileDownloadCache()

@property (nonatomic) NSString *URL;

@end

@implementation BAFileDownloadCache

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

- (BAFileDownloadCacheState)state
{
    BAFileDownloadCacheDB *sharedDB = [BAFileDownloadCacheDB sharedDB];
    NSString *taskKey = [self.URL BAFD_MD5];
    BAFileDownloadCacheDBTaskInfo *oldTaskInfo = [sharedDB getTaskInfo:taskKey];
    BAFileDownloadCacheState result = oldTaskInfo.state;
    if (oldTaskInfo.state == BAFileDownloadCacheStateFull) {
        if (![self isPathExist:[self cachedFullDataPath]]) {
            [sharedDB updateTaskInfo:taskKey md5:nil fullLength:oldTaskInfo.fullLength state:BAFileDownloadCacheStatePart];
            result = BAFileDownloadCacheStatePart;
        }
    }
    return result;
}

- (NSError *)updateSlicesSheet:(NSInteger)fullDataLength sliceSize:(NSInteger)sliceSize
{
    BAFileDownloadCacheDB *sharedDB = [BAFileDownloadCacheDB sharedDB];
    NSString *taskKey = [self.URL BAFD_MD5];
    BAFileDownloadCacheDBTaskInfo *oldInfo = [sharedDB getTaskInfo:taskKey];
    [sharedDB updateTaskInfo:taskKey md5:oldInfo.md5 fullLength:fullDataLength state:BAFileDownloadCacheStatePart];
    NSInteger sliceCount = ceil((CGFloat)fullDataLength / (CGFloat)sliceSize);
    for (NSInteger i=0; i<sliceCount; i++) {
        NSInteger location = sliceSize * i;
        NSInteger destination = sliceSize * (i + 1);
        if (destination > fullDataLength) {
            destination = fullDataLength;
        }
        [[BAFileDownloadCacheDB sharedDB] updateSliceInfo:[self.URL BAFD_MD5] sliceKey:NSStringFromRange(NSMakeRange(location, destination - location)) state:BAFileLocalCacheSliceStateNull];
    }
    return nil;
}

- (NSUInteger)getFullDataLength
{
    BAFileDownloadCacheDBTaskInfo *result = [[BAFileDownloadCacheDB sharedDB] getTaskInfo:[self.URL BAFD_MD5]];
    return result.fullLength;
}

- (NSString *)getFullDataMD5
{
    BAFileDownloadCacheDBTaskInfo *result = [[BAFileDownloadCacheDB sharedDB] getTaskInfo:[self.URL BAFD_MD5]];
    return result.md5;
}

- (NSUInteger)getCachedSliceLength
{
    NSArray *allSlicesKey = [[BAFileDownloadCacheDB sharedDB] getSlicesKey:[self.URL BAFD_MD5] sliceState:BAFileLocalCacheSliceStateSuccessed];
    NSUInteger result = 0;
    for (NSString *rangeString in allSlicesKey) {
        NSRange range = NSRangeFromString(rangeString);
        result = result + range.length;
    }
    return result;
}

- (NSArray *)getUncachedSliceRanges
{
    NSMutableArray *result = nil;
    NSArray *errorSlices = [[BAFileDownloadCacheDB sharedDB] getSlicesKey:[self.URL BAFD_MD5] sliceState:BAFileLocalCacheSliceStateError];
    if (errorSlices) {
        if (!result) {
            result = [[NSMutableArray alloc] init];
        }
        [result addObjectsFromArray:errorSlices];
    }
    NSArray *nullSlices = [[BAFileDownloadCacheDB sharedDB] getSlicesKey:[self.URL BAFD_MD5] sliceState:BAFileLocalCacheSliceStateNull];
    if (nullSlices) {
        if (!result) {
            result = [[NSMutableArray alloc] init];
        }
        [result addObjectsFromArray:nullSlices];
    }
    return result;
}

- (NSArray *)getFailedSliceRanges
{
    return [[BAFileDownloadCacheDB sharedDB] getSlicesKey:[self.URL BAFD_MD5] sliceState:BAFileLocalCacheSliceStateError];
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
    NSString *taskKey = [self.URL BAFD_MD5];
    BAFileDownloadCacheDB *sharedDB = [BAFileDownloadCacheDB sharedDB];
    NSString *rangeString = NSStringFromRange(sliceRange);
    if (error) {
        [sharedDB updateSliceInfo:taskKey sliceKey:rangeString state:BAFileLocalCacheSliceStateError];
        BAFileDownloadCacheDBTaskInfo *oldTaskInfo = [sharedDB getTaskInfo:taskKey];
        [sharedDB updateTaskInfo:taskKey md5:oldTaskInfo.md5 fullLength:oldTaskInfo.fullLength state:BAFileDownloadCacheStatePart];
        return error;
    } else {
        if ([self isPathExist:dataPath]) {
            //1.copy slice data file from sand box path to given path
            NSString *slicePath = [self cachedSliceDataPathWithSliceFlag:rangeString];
            [self moveFileFrom:dataPath to:slicePath overWrite:YES];
            [sharedDB updateSliceInfo:taskKey sliceKey:rangeString state:BAFileLocalCacheSliceStateSuccessed];
            
            BAFileDownloadCacheState tmpState = BAFileDownloadCacheStatePart;
            NSArray *errorSlices = [sharedDB getSlicesKey:taskKey sliceState:BAFileLocalCacheSliceStateError];
            NSArray *nullSlices = [sharedDB getSlicesKey:taskKey sliceState:BAFileLocalCacheSliceStateNull];
            if ((!errorSlices || errorSlices.count == 0) && (!nullSlices || nullSlices.count == 0)) {
                tmpState = BAFileDownloadCacheStateFull;
            }
            BAFileDownloadCacheDBTaskInfo *oldTaskInfo = [sharedDB getTaskInfo:taskKey];
            if (tmpState == BAFileDownloadCacheStateFull) {
                //2.merge all slices if all of it saved
                return [self mergeAllSlicesData];
            } else {
                [sharedDB updateTaskInfo:taskKey md5:oldTaskInfo.md5 fullLength:oldTaskInfo.fullLength state:tmpState];
                return nil;
            }
        } else {
            return [NSError BAFD_simpleErrorWithDescription:@"slice file invalid"];
        }
    }
}

- (NSError *)mergeAllSlicesData
{
    __block NSError *tmpError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [self mergeAllSlicesDataWithFinishedBlock:^(NSError *mergeActionError){
        tmpError = mergeActionError;
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    //3.get md5 value
    NSString *taskKey = [self.URL BAFD_MD5];
    BAFileDownloadCacheDB *sharedDB = [BAFileDownloadCacheDB sharedDB];
    BAFileDownloadCacheDBTaskInfo *oldTaskInfo = [sharedDB getTaskInfo:taskKey];
    if (!tmpError) {
        oldTaskInfo.md5 = [BAStreamFileMD5 md5:[self cachedFullDataPath]];
    }
    
    //4.update cache info
    if (!tmpError) {
        oldTaskInfo.state = BAFileDownloadCacheStateFull;
        [sharedDB updateTaskInfo:taskKey md5:oldTaskInfo.md5 fullLength:oldTaskInfo.fullLength state:oldTaskInfo.state];
        [sharedDB deleteSliceInfoTable:taskKey];
        [self removeFilesAtPath:[self slicesPoolPath]];
        [self createDirectoryAtPath:[self slicesPoolPath]];
    }
    return tmpError;
}

- (NSString *)fullDataPath
{
    return [self state] == BAFileDownloadCacheStateFull ? [self cachedFullDataPath] : nil;
}

- (void)cleanCache
{
    
}

#pragma mark - private method
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
    NSMutableArray *allSlices = [[BAFileDownloadCacheDB sharedDB] getAllSlicesKey:[self.URL BAFD_MD5]].mutableCopy;
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
