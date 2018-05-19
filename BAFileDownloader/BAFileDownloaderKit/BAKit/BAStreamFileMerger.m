//
//  BAStreamFileMerger.m
//  BAFileDownloader
//
//  Created by nds on 2017/12/12.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "BAStreamFileMerger.h"
#import "NSError+BAFileDownloaderCategory.h"
#import "NSString+BAFileDownloaderCategory.h"

typedef void(^BAStreamFileMergerFinishedBlock)(NSError *error);

@interface BAStreamFileMerger() <NSStreamDelegate>

@property (nonatomic) NSMutableArray *unmergedFilePaths;

@property (nonatomic) NSInputStream *inputStream;
@property (nonatomic) NSOutputStream *outputStream;

@property (nonatomic) NSArray *slicePaths;
@property (nonatomic) NSString *targetPath;
@property (nonatomic) BAStreamFileMergerFinishedBlock finishedBlock;

@property (nonatomic) BOOL isLastSlice;

@end

@implementation BAStreamFileMerger

- (void)dealloc
{
    [self closeInputStream];
    [self closeOutputStream];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _unmergedFilePaths = [[NSMutableArray alloc] init];
    }
    return self;
}

#pragma mark - public method
+ (void)mergeFiles:(NSArray <NSString *> *)slicesPaths into:(NSString *)targetPath finishedBlock:(void(^)(NSError *error))finishedBlock
{
    if (!slicesPaths || slicesPaths.count == 0 || !targetPath || targetPath.length == 0) {
        if (finishedBlock) {
            finishedBlock([NSError BAFD_simpleErrorWithDescription:@"slices info error"]);
        }
        return;
    }
    dispatch_async([self sharedActionQueue], ^() {
        BAStreamFileMerger *merger = [[BAStreamFileMerger alloc] init];
        [BAStreamFileMerger registerLiving:merger];//keep merger alive
        
        merger.targetPath = targetPath;
        merger.finishedBlock = finishedBlock;
        merger.unmergedFilePaths = slicesPaths.mutableCopy;
        
        [merger performSelector:@selector(startMergeAction) onThread:[BAStreamFileMerger sharedThread] withObject:nil waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
    });
}

- (void)startMergeAction
{
    if (!self.unmergedFilePaths || self.unmergedFilePaths == 0) {
        [self mergeActionFinished:[NSError BAFD_simpleErrorWithDescription:@"file paths null"]];
    } else if (![self.targetPath BAFD_isValid]) {
        [self mergeActionFinished:[NSError BAFD_simpleErrorWithDescription:@"target path invalid"]];
    } else {
        [self removeFilesAtPath:self.targetPath];
        NSError *error = [self startInputWithFilePath:self.unmergedFilePaths.firstObject];
        if (error) {
            [self mergeActionFinished:error];
        }
    }
}

#pragma mark - NSStreamDelegate
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
            break;
        }
        case NSStreamEventHasBytesAvailable: {
            if ([aStream isKindOfClass:[NSInputStream class]]) {
                NSInputStream *inputStream = (NSInputStream *)aStream;
                if ([inputStream hasBytesAvailable]) {
                    NSInteger bufferSize = 1024;
                    uint8_t buffer[bufferSize];
                    NSInteger readedLength = [((NSInputStream *)aStream) read:buffer maxLength:(NSUInteger)sizeof(buffer)];
                    if (!self.isLastSlice) {
                        //last byte might be end flag of slice file, so drop it befor last slice
                        readedLength = readedLength == bufferSize ? readedLength: readedLength - 1;
                    }
                    if (readedLength > 0) {
                        NSInteger writedLength = [self write:buffer maxLength:readedLength];
                        if (writedLength == 0) {
                            [self mergeActionFinished:nil];
                        }
                    } else {
                        [self skipToNextFilePathMerge];
                    }
                } else {
                    [self skipToNextFilePathMerge];
                }
            }
            break;
        }
        case NSStreamEventHasSpaceAvailable: {
            if ([aStream isKindOfClass:[NSOutputStream class]]) {
                NSOutputStream *outputStream = (NSOutputStream *)aStream;
                if (![outputStream hasSpaceAvailable]) {
                    [self mergeActionFinished:[NSError BAFD_simpleErrorWithDescription:@"output stream has no space available"]];
                }
            }
            break;
        }
        case NSStreamEventErrorOccurred: {
            if ([aStream isKindOfClass:[NSInputStream class]]) {
                [self mergeActionFinished:[NSError BAFD_simpleErrorWithDescription:@"input stream error"]];
            } else if ([aStream isKindOfClass:[NSOutputStream class]]) {
                [self mergeActionFinished:[NSError BAFD_simpleErrorWithDescription:@"output stream error"]];
            } else {
                [self mergeActionFinished:nil];
            }
            break;
        }
        case NSStreamEventEndEncountered: {
            if ([aStream isKindOfClass:[NSInputStream class]]) {
                [self skipToNextFilePathMerge];
            } else {
                [self mergeActionFinished:nil];
            }
            break;
        }
        default:
            break;
    }
}

#pragma mark - private method
#pragma mark thread method
+ (dispatch_queue_t)sharedActionQueue
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t _actionQueue;
    dispatch_once(&onceToken, ^{
        _actionQueue = dispatch_queue_create("com.BAFileDownloader.BAStreamFileMerger", DISPATCH_QUEUE_SERIAL);
    });
    return _actionQueue;
}

+ (void) __attribute__((noreturn)) sharedThreadEntryPoint:(id)__unused object {
    do {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] run];//keep thread alive
        }
    } while (YES);
}

+ (NSThread *)sharedThread
{
    static dispatch_once_t onceToken;
    static NSThread *sharedThread;
    dispatch_once(&onceToken, ^{
        sharedThread = [[NSThread alloc] initWithTarget:self selector:@selector(sharedThreadEntryPoint:) object:nil];
        [sharedThread start];
    });
    return sharedThread;
}

#pragma mark life cycle control method
+ (NSMutableSet *)livingMergers
{
    static NSMutableSet *livingMergers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        livingMergers = [[NSMutableSet alloc] init];
    });
    return livingMergers;
}

+ (void)registerLiving:(BAStreamFileMerger *)merger
{
    if (merger) {
        [[self livingMergers] addObject:merger];
    }
}

+ (void)unregisterLiving:(BAStreamFileMerger *)merger
{
    if (merger) {
        [[self livingMergers] performSelectorOnMainThread:@selector(removeObject:) withObject:merger waitUntilDone:NO];
    }
}

#pragma mark stream method
- (NSError *)startInputWithFilePath:(NSString *)filePath
{
    if (![filePath BAFD_isValid] || ![self isPathExist:filePath]) {
        return [NSError BAFD_simpleErrorWithDescription:@"input file paths invalid"];
    } else {
        if (!self.inputStream) {
            self.inputStream = [[NSInputStream alloc] initWithFileAtPath:filePath];
            self.inputStream.delegate = self;
            [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
            [self.inputStream open];
        }
        return nil;
    }
}

- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len
{
    if (!self.outputStream) {
        self.outputStream = [[NSOutputStream alloc] initToFileAtPath:self.targetPath append:YES];
        self.outputStream.delegate = self;
        [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [self.outputStream open];
    }
    return [self.outputStream write:buffer maxLength:len];
}

- (void)closeAllStream
{
    [self closeInputStream];
    [self closeOutputStream];
}

- (void)closeInputStream
{
    if (self.inputStream) {
        [self.inputStream close];
        [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        self.inputStream = nil;
    }
}

- (void)closeOutputStream
{
    if (self.outputStream) {
        [self.outputStream close];
        [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        self.outputStream = nil;
    }
}

#pragma mark file method
- (BOOL)isPathExist:(NSString *)path
{
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (void)removeFilesAtPath:(NSString *)path
{
    if ([self isPathExist:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

#pragma mark others
- (void)skipToNextFilePathMerge
{
    if (self.unmergedFilePaths.count == 0) {
        [self mergeActionFinished:nil];
    } else {
        [self closeInputStream];
        [self.unmergedFilePaths removeObject:self.unmergedFilePaths.firstObject];
        if (self.unmergedFilePaths.count == 0) {
            [self mergeActionFinished:nil];
        } else {
            if (self.unmergedFilePaths.count == 1) {
                self.isLastSlice = YES;
            }
            NSError *error = [self startInputWithFilePath:self.unmergedFilePaths.firstObject];
            if (error) {
                [self mergeActionFinished:error];
            }
        }
    }
}

- (void)mergeActionFinished:(NSError *)error
{
    [self closeAllStream];
    __weak typeof(self) weakSelf = self;
    dispatch_async([[self class] sharedActionQueue], ^() {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf.unmergedFilePaths removeAllObjects];
        if (error) {
            [strongSelf removeFilesAtPath:strongSelf.targetPath];
        }
        if (strongSelf.finishedBlock) {
            strongSelf.finishedBlock(error);
        }
        [BAStreamFileMerger unregisterLiving:strongSelf];
    });
}

@end
