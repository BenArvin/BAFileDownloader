//
//  BAFileDownloadOperation.m
//  BAFileDownloader
//
//  Created by nds on 2017/12/1.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "BAFileDownloadOperation.h"
#import "BAFileDownloadTask.h"
#import "NSString+BAFileDownloaderCategory.h"
#import "BAFileDownloadSession.h"
#import "NSError+BAFileDownloaderCategory.h"
#import "BAFileDownloadCache.h"
#import "BAFileDownloadThreads.h"

#define TIMES_FAILED_RETRY 3

@interface BAFileDownloadOperation()

@property (atomic) BOOL running;

@property (nonatomic) BAFileDownloadCache *localCache;

@property (nonatomic, readwrite) NSString *URL;
@property (nonatomic) NSString *fileMD5;
@property (nonatomic) BOOL useSliceMode;
@property (nonatomic) NSUInteger sliceSize;
@property (nonatomic) NSUInteger finishedLength;

@property (nonatomic) NSInteger retryingTime;
@property (nonatomic) NSError *operationError;

@property (nonatomic) NSMutableArray *tasks;

@end

@implementation BAFileDownloadOperation

- (instancetype)init
{
    self = [super init];
    if (self) {
        _tasks = [[NSMutableArray alloc] init];
        
        _retryingTime = 0;
        _useSliceMode = YES;
        _sliceSize = 1024 * 10;
    }
    return self;
}

#pragma mark - property methods
- (void)setFinishedLength:(NSUInteger)finishedLength
{
    if (_finishedLength != finishedLength) {
        _finishedLength = finishedLength;
        NSUInteger fullDataLength = [self.localCache getFullDataLength];
        for (BAFileDownloadTask *task in self.tasks) {
            if (task.progressBlock) {
                __weak typeof(self) weakSelf = self;
                [[BAFileDownloadThreads outputQueue] addOperationWithBlock:^(){
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    task.progressBlock(strongSelf.URL, finishedLength, fullDataLength);
                }];
            }
        }
    }
}

#pragma mark - public method
- (void)addTask:(BAFileDownloadTask *)task
{
    if (!task || [self.tasks containsObject:task]) {
        return;
    }
    if (self.tasks.count == 0) {
        self.URL = task.URL;
        self.fileMD5 = task.fileMD5;
        self.useSliceMode = task.useSliceMode;
        self.sliceSize = task.sliceSize;
        
        self.localCache = [[BAFileDownloadCache alloc] initWithURL:task.URL];
    }
    [self.tasks addObject:task];
}

- (void)removeTask:(BAFileDownloadTask *)task
{
    if (!task || ![self.tasks containsObject:task]) {
        return;
    }
    [self.tasks removeObject:task];
}

- (void)start
{
    if (![self.URL BAFD_isValid] || self.running) {
        return;
    }
    self.running = YES;
    self.retryingTime = self.retryingTime + 1;
    self.operationError = nil;
    if (self.localCache.state == BAFileDownloadCacheStateNull) {
        //1.get full content length & accept ranges?
        __weak typeof(self) weakSelf1 = self;
        [self getRemoteResourceInfoForURL:self.URL finishedBlock:^(BOOL acceptRanges, NSInteger contentLength, NSError *error) {
            __strong typeof(weakSelf1) strongSelf1 = weakSelf1;
            if (!error) {
                //2.update cache info & build slice sheet
                [strongSelf1.localCache updateSlicesSheet:contentLength sliceSize:(strongSelf1.useSliceMode && acceptRanges) ? strongSelf1.sliceSize : contentLength];
                //3.download & cache slices
                [strongSelf1 downloadAndCacheSlicesData];
            } else {
                strongSelf1.operationError = error;
                [strongSelf1 operationFinished];
            }
        }];
    } else if (self.localCache.state == BAFileDownloadCacheStatePart) {
        [self downloadAndCacheSlicesData];
    } else {
        [self operationFinished];
    }
}

- (void)pause
{
    if (!self.running) {
        return;
    }
    self.running = NO;
}

#pragma mark - private method
#pragma mark network method
- (void)getRemoteResourceInfoForURL:(NSString *)URL finishedBlock:(void(^)(BOOL acceptRanges, NSInteger contentLength, NSError *error))finishedBlock
{
    if (![self.URL BAFD_isValid]) {
        if (finishedBlock) {
            finishedBlock(NO, 0, [NSError BAFD_simpleErrorWithDescription:@"invalid URL"]);
        }
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.URL]];
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    request.HTTPMethod = @"HEAD";
    [[BAFileDownloadSession sharedSession] startDataTask:request completionHandler:^(NSURLResponse *response, NSError *error) {
        BOOL acceptRanges = NO;
        NSInteger contentLength = 0;
        NSError *responseError = nil;
        if (!error && [response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *responseTmp = (NSHTTPURLResponse *)response;
            NSInteger statusCode = [responseTmp statusCode];
            if (statusCode != 200) {
                responseError = [NSError BAFD_simpleErrorWithDescription:[NSString stringWithFormat:@"response code %ld", statusCode]];
            } else {
                NSDictionary *result = responseTmp.allHeaderFields;
                if (result) {
                    NSString *acceptRangesString = [result objectForKey:@"Accept-Ranges"];
                    if (acceptRangesString) {
                        acceptRanges = ([acceptRangesString rangeOfString:@"bytes"].location != NSNotFound);
                    }
                    contentLength = ((NSNumber *)[result objectForKey:@"Content-Length"]).integerValue;
                } else {
                    error = [NSError BAFD_simpleErrorWithDescription:@"unrecognized response"];
                }
            }
        } else {
            responseError = error ? error : [NSError BAFD_simpleErrorWithDescription:@"unrecognized response"];
        }
        if (finishedBlock) {
            [[BAFileDownloadThreads actionQueue] addOperationWithBlock:^() {
                finishedBlock(acceptRanges, contentLength, responseError);
            }];
        }
    }];
}

- (void)downloadAndCacheSlicesData
{
    //1.get uncached slices info
    NSArray *sliceRanges = [self.localCache getUncachedSliceRanges];
    if (!sliceRanges || sliceRanges.count == 0) {
        self.operationError = [NSError BAFD_simpleErrorWithDescription:@"get slice ranges failed!"];
        [self operationFinished];
        return;
    }
    //2.get downloaded data length
    self.finishedLength = [self.localCache getCachedSliceLength];
    
    //3.start download slices
    __block NSInteger count = sliceRanges.count;
    for (NSString *rangeString in sliceRanges) {
        NSRange range = NSRangeFromString(rangeString);
        
        //4.build net request for each slice
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.URL]];
        [request setValue:[NSString stringWithFormat:@"Bytes=%lu-%lu", range.location, range.location + range.length] forHTTPHeaderField:@"Range"];
        
        //5.start net request
        __weak typeof(self) weakSelf1 = self;
        [[BAFileDownloadSession sharedSession] startDownloadTask:request progressHandler:^(NSUInteger finished, NSUInteger totalFinished, NSUInteger totalExpected) {
            __strong typeof(weakSelf1) strongSelf1 = weakSelf1;
            [strongSelf1 updateProgress:finished totalFinished:totalFinished totalExpected:totalExpected];
        } completionHandler:^(NSURL *location, NSError *error) {
            __strong typeof(weakSelf1) strongSelf1 = weakSelf1;
            //6.copy tmp file from NSURLSession tmp files path to sand box synchronized, in case tmp file removed
            NSString *netResponseTmpFilePath = nil;
            if (!error && location) {
                netResponseTmpFilePath = location.relativePath;
            }
            NSString *cachedTmpFilePath = [strongSelf1.localCache cacheNetResponseTmpSliceData:netResponseTmpFilePath sliceRange:range];
            
            //7.save net response
            __weak typeof(strongSelf1) weakSelf2 = strongSelf1;
            [[BAFileDownloadThreads actionQueue] addOperationWithBlock:^() {
                __strong typeof(weakSelf2) strongSelf2 = weakSelf2;
                NSError *saveActionError = [strongSelf2.localCache saveSliceData:cachedTmpFilePath error:error sliceRange:range];
                count--;
                strongSelf2.operationError = saveActionError;
                if (count == 0) {
                    //8.operation finished if all requsets finished
                    [strongSelf2 updateProgressWhenOperationFinished];
                    [strongSelf2 operationFinished];
                }
            }];
        }];
    }
}

#pragma mark progress methods
- (void)updateProgress:(NSUInteger)finished totalFinished:(NSUInteger)totalFinished totalExpected:(NSUInteger)totalExpected
{
    //last one byte of slice is file ending flag
    NSUInteger finishedLengthTmp = (totalFinished == totalExpected ? finished - 1 : finished);
    self.finishedLength = self.finishedLength + finishedLengthTmp;
}

- (void)updateProgressWhenOperationFinished
{
    //last one byte of last slice is needed
    self.finishedLength = self.finishedLength + 1;
}

#pragma mark others
- (void)operationFinished
{
    [self pause];
    if (self.operationError || self.localCache.state != BAFileDownloadCacheStateFull) {
        if (self.retryingTime < TIMES_FAILED_RETRY) {
            //retry
            [self start];
            return;
        }
    }
    for (BAFileDownloadTask *task in self.tasks) {
        if (task.finishedBlock) {
            __weak typeof(self) weakSelf = self;
            [[BAFileDownloadThreads outputQueue] addOperationWithBlock:^(){
                __strong typeof(weakSelf) strongSelf = weakSelf;
                task.finishedBlock(strongSelf.URL, [strongSelf.localCache fullDataPath], strongSelf.operationError);
            }];
        }
    }
    if ([self.delegate respondsToSelector:@selector(fileDownloadOperation:finished:)]) {
        [self.delegate fileDownloadOperation:self finished:nil];
    }
}

@end
