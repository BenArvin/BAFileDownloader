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
#import "BAFileDownloaderSession.h"
#import "NSError+BAFileDownloaderCategory.h"
#import "BAFileDownloaderLocalCache.h"
#import "BAFileDownloaderThreads.h"

@interface BAFileDownloadOperation()

@property (atomic) BOOL running;

@property (nonatomic) BAFileDownloaderLocalCache *localCache;

@property (nonatomic, readwrite) NSString *URL;
@property (nonatomic) NSString *fileMD5;
@property (nonatomic) BOOL inFragmentMode;
@property (nonatomic) NSUInteger fragmentSize;

@property (nonatomic) NSError *operationError;

@property (nonatomic) NSMutableArray *tasks;

@end

@implementation BAFileDownloadOperation

- (instancetype)init
{
    self = [super init];
    if (self) {
        _tasks = [[NSMutableArray alloc] init];
        
        _inFragmentMode = YES;
        _fragmentSize = 1024 * 10;
    }
    return self;
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
        self.inFragmentMode = task.inFragmentMode;
        self.fragmentSize = task.fragmentSize;
        
        self.localCache = [[BAFileDownloaderLocalCache alloc] initWithURL:task.URL];
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
    if (self.localCache.state == BAFileDownloaderLocalCacheStateNull) {
        //1.get full content length & accept ranges?
        __weak typeof(self) weakSelf1 = self;
        [self getRemoteResourceInfoForURL:self.URL finishedBlock:^(BOOL acceptRanges, NSInteger contentLength, NSError *error) {
            __strong typeof(weakSelf1) strongSelf1 = weakSelf1;
            if (!error) {
                //2.update cache info & build slice sheet
                [strongSelf1.localCache updateSlicesSheet:contentLength sliceSize:(strongSelf1.inFragmentMode && acceptRanges) ? strongSelf1.fragmentSize : contentLength];
                //3.download & cache slices
                [strongSelf1 downloadAndCacheSlicesData];
            } else {
                strongSelf1.operationError = error;
            }
        }];
    } else if (self.localCache.state == BAFileDownloaderLocalCacheStatePart) {
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
    [[BAFileDownloaderSession sharedSession] startDataTask:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        BOOL acceptRanges = NO;
        NSInteger contentLength = 0;
        NSError *responseError = nil;
        if (!error && [response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSDictionary *result = ((NSHTTPURLResponse *)response).allHeaderFields;
            if (result) {
                NSString *acceptRangesString = [result objectForKey:@"Accept-Ranges"];
                if (acceptRangesString) {
                    acceptRanges = ([acceptRangesString rangeOfString:@"bytes"].location != NSNotFound);
                }
                contentLength = ((NSNumber *)[result objectForKey:@"Content-Length"]).integerValue;
            } else {
                error = [NSError BAFD_simpleErrorWithDescription:@"unrecognized response"];
            }
        } else {
            responseError = error ? error : [NSError BAFD_simpleErrorWithDescription:@"unrecognized response"];
        }
        if (finishedBlock) {
            [[BAFileDownloaderThreads actionQueue] addOperationWithBlock:^() {
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
    //2.start download slices
    __block NSInteger count = sliceRanges.count;
    for (NSString *rangeString in sliceRanges) {
        NSRange range = NSRangeFromString(rangeString);
        
        //3.build net request for each slice
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.URL]];
        [request setValue:[NSString stringWithFormat:@"Bytes=%lu-%lu", range.location, range.location + range.length] forHTTPHeaderField:@"Range"];
        
        //4.start net request
        __weak typeof(self) weakSelf1 = self;
        [[BAFileDownloaderSession sharedSession] startDownloadTask:request completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            __strong typeof(weakSelf1) strongSelf1 = weakSelf1;
            //5.copy tmp file from NSURLSession tmp files path to sand box synchronized, in case tmp file removed
            NSString *netResponseTmpFilePath = nil;
            if (!error && location) {
                netResponseTmpFilePath = location.relativePath;
            }
            NSString *cachedTmpFilePath = [strongSelf1.localCache cacheNetResponseTmpSliceData:netResponseTmpFilePath sliceRange:range];
            
            //6.save net response
            __weak typeof(strongSelf1) weakSelf2 = strongSelf1;
            [[BAFileDownloaderThreads actionQueue] addOperationWithBlock:^() {
                __strong typeof(weakSelf2) strongSelf2 = weakSelf2;
                NSError *saveActionError = [strongSelf2.localCache saveSliceData:cachedTmpFilePath error:error sliceRange:range];
                count--;
                strongSelf2.operationError = saveActionError;
                if (count == 0) {
                    //7.operation finished if all requsets finished
                    [strongSelf2 operationFinished];
                }
            }];
        }];
    }
}

#pragma mark others
- (void)operationFinished
{
    for (BAFileDownloadTask *task in self.tasks) {
        if (task.finishedBlock) {
            __weak typeof(self) weakSelf = self;
            [[BAFileDownloaderThreads outputQueue] addOperationWithBlock:^(){
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
