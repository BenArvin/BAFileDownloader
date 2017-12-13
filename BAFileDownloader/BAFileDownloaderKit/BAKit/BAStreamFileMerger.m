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
+ (void)mergeFiles:(NSArray <NSString *> *)silcesPaths into:(NSString *)targetPath finishedBlock:(void(^)(NSError *error))finishedBlock
{
    BAStreamFileMerger *merger = [[BAStreamFileMerger alloc] init];
    [BAStreamFileMerger registerLiving:merger];//keep merger alive
    
    merger.targetPath = targetPath;
    merger.finishedBlock = finishedBlock;
    merger.unmergedFilePaths = silcesPaths.mutableCopy;
    
    [merger performSelector:@selector(startMergeAction) onThread:[BAStreamFileMerger sharedThread] withObject:nil waitUntilDone:NO modes:@[NSRunLoopCommonModes]];
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
                    uint8_t buffer[1024];
                    NSInteger readedLength = [((NSInputStream *)aStream) read:buffer maxLength:(NSUInteger)sizeof(buffer)];
                    if (readedLength > 0) {
                        NSInteger writedLength = [self write:buffer maxLength:(NSUInteger)sizeof(buffer)];
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
    [self.unmergedFilePaths removeAllObjects];
    if (error) {
        [self removeFilesAtPath:self.targetPath];
    }
    if (self.finishedBlock) {
        self.finishedBlock(error);
    }
    self.finishedBlock = nil;
    [BAStreamFileMerger unregisterLiving:self];
}

@end
