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

@interface BAFileDownloadOperation()

@property (atomic) BOOL running;

@property (nonatomic) BAFileDownloaderLocalCache *localCache;

@property (nonatomic, readwrite) NSString *URL;
@property (nonatomic) NSString *fileMD5;
@property (nonatomic) BOOL inFragmentMode;
@property (nonatomic) NSUInteger fragmentSize;

@property (nonatomic) NSError *operationError;

@property (nonatomic) NSMutableArray *tasks;
@property (nonatomic) NSOperationQueue *operationQueue;
@property (nonatomic) NSOperationQueue *networkQueue;

@end

@implementation BAFileDownloadOperation

- (void)dealloc
{
    if (_operationQueue) {
        [_operationQueue cancelAllOperations];
    }
    if (_networkQueue) {
        [_networkQueue cancelAllOperations];
    }
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _tasks = [[NSMutableArray alloc] init];
        
        _operationQueue = [[NSOperationQueue alloc] init];
        _operationQueue.name = @"BAFileDownloadOperationQueue";
        _operationQueue.maxConcurrentOperationCount = 1;
        
        _networkQueue = [[NSOperationQueue alloc] init];
        _networkQueue.name = @"BAFileDownloadOperationNetworkQueue";
        _networkQueue.maxConcurrentOperationCount = 5;
        
        _inFragmentMode = YES;
        _fragmentSize = 1024 * 10;
    }
    return self;
}

#pragma mark - public method
- (void)addTask:(BAFileDownloadTask *)task
{
    __weak typeof(self) weakSelf = self;
    [self.operationQueue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!task || [strongSelf.tasks containsObject:task]) {
            return;
        }
        if (strongSelf.tasks.count == 0) {
            strongSelf.URL = task.URL;
            strongSelf.fileMD5 = task.fileMD5;
            strongSelf.inFragmentMode = task.inFragmentMode;
            strongSelf.fragmentSize = task.fragmentSize;
            
            strongSelf.localCache = [[BAFileDownloaderLocalCache alloc] initWithURL:task.URL];
        }
        [strongSelf.tasks addObject:task];
    }];
}

- (void)removeTask:(BAFileDownloadTask *)task
{
    __weak typeof(self) weakSelf = self;
    [self.operationQueue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!task || ![strongSelf.tasks containsObject:task]) {
            return;
        }
        [strongSelf.tasks removeObject:task];
    }];
}

- (void)start
{
    __weak typeof(self) weakSelf = self;
    [self.operationQueue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![strongSelf.URL BAFD_isValid] || strongSelf.running) {
            return;
        }
        strongSelf.running = YES;
        
        if (strongSelf.localCache.state == BAFileDownloaderLocalCacheStateFull) {
            return;//already full cached
        } else if (strongSelf.localCache.state == BAFileDownloaderLocalCacheStateNull) {
            //1.get full content length & accept ranges?
            __weak typeof(strongSelf) weakSelf2 = strongSelf;
            [strongSelf getRemoteResourceInfoForURL:strongSelf.URL finishedBlock:^(BOOL acceptRanges, NSInteger contentLength, NSError *error) {
                __strong typeof(weakSelf2) strongSelf2 = weakSelf2;
                if (!error) {
                    //2.update cache info & build slice sheet
                    __weak typeof(strongSelf2) weakSelf3 = strongSelf2;
                    [strongSelf2.localCache updateSlicesSheet:contentLength sliceSize:(strongSelf2.inFragmentMode && acceptRanges) ? strongSelf2.fragmentSize : contentLength finishedBlock:^(NSError *error){
                        __strong typeof(weakSelf3) strongSelf3 = weakSelf3;
                        //3.download & cache slices
                        [strongSelf3 downloadAndCacheSlicesData];
                    }];
                }
            }];
        } else if (strongSelf.localCache.state == BAFileDownloaderLocalCacheStatePart) {
            [strongSelf downloadAndCacheSlicesData];
        }
    }];
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
    __weak typeof(self) weakSelf = self;
    [self.networkQueue addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![strongSelf.URL BAFD_isValid]) {
            if (finishedBlock) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){
                    finishedBlock(NO, 0, [NSError BAFD_simpleErrorWithDescription:@"invalid URL"]);
                });
            }
            return;
        }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:strongSelf.URL]];
        request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        request.HTTPMethod = @"HEAD";
        NSURLSessionDataTask *sessionTask = [[BAFileDownloaderSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (!error && [response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSDictionary *result = ((NSHTTPURLResponse *)response).allHeaderFields;
                NSString *acceptRanges = [result objectForKey:@"Accept-Ranges"];
                if (finishedBlock) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){
                        finishedBlock([acceptRanges rangeOfString:@"bytes"].location != NSNotFound,
                                      ((NSNumber *)[result objectForKey:@"Content-Length"]).integerValue,
                                      nil);
                    });
                }
            } else {
                if (finishedBlock) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(){
                        finishedBlock(NO, 0, error ? error : [NSError BAFD_simpleErrorWithDescription:@"unrecognized response"]);
                    });
                }
            }
        }];
        [sessionTask resume];
    }];
}

- (void)downloadAndCacheSlicesData
{
    //1.get uncached slices info
    __weak typeof(self) weakSelf = self;
    [self.localCache getUncachedSliceRanges:^(NSArray *sliceRanges) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        //2.start download slices
        __block NSInteger count = sliceRanges.count;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(5);
        for (NSString *rangeString in sliceRanges) {
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            NSRange range = NSRangeFromString(rangeString);
            __weak typeof(strongSelf) weakSelf2 = strongSelf;
            [strongSelf.networkQueue addOperationWithBlock:^{
                __strong typeof(weakSelf2) strongSelf2 = weakSelf2;
                //3.build net request for each slice
                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:strongSelf2.URL]];
                [request setValue:[NSString stringWithFormat:@"Bytes=%lu-%lu", range.location, range.location + range.length] forHTTPHeaderField:@"Range"];
                __weak typeof(strongSelf2) weakSelf3 = strongSelf2;
                NSURLSessionDownloadTask *sessionTask = [[BAFileDownloaderSession sharedSession] downloadTaskWithRequest:request completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    __strong typeof(weakSelf3) strongSelf3 = weakSelf3;
                    __weak typeof(strongSelf3) weakSelf4 = strongSelf3;
                    //4.save net response
                    [strongSelf3.localCache saveSliceData:location ? location.relativePath : nil error:error sliceRange:range finishedBlock:^(NSError *saveActionError){
                        __strong typeof(weakSelf4) strongSelf4 = weakSelf4;
                        count--;
                        strongSelf4.operationError = saveActionError;
                        if (count == 0) {
                            //5.operation finished if all requsets finished
                            [strongSelf4 operationFinished];
                        }
                        dispatch_semaphore_signal(semaphore);
                    }];
                }];
                [sessionTask resume];
            }];
        }
    }];
}

#pragma mark others
- (void)operationFinished
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        for (BAFileDownloadTask *task in strongSelf.tasks) {
            if (task.finishedBlock) {
                task.finishedBlock(strongSelf.URL, [strongSelf.localCache fullDataPath], strongSelf.operationError);
            }
        }
    });
}

@end
