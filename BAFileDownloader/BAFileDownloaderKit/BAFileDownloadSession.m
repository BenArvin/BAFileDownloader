//
//  BAFileDownloadSession.m
//  BAFileDownloader
//
//  Created by nds on 2017/12/6.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "BAFileDownloadSession.h"
#import "BAFileDownloadThreads.h"

@interface BAFileDownloadSession() <NSURLSessionDelegate, NSURLSessionDownloadDelegate, NSURLSessionDataDelegate>

@property (nonatomic) NSURLSession *session;
@property (nonatomic) NSMutableDictionary *taskHandlerDic;
@property (nonatomic) NSRecursiveLock *lock;

@end

@implementation BAFileDownloadSession

- (void)dealloc
{
    if (self.session) {
        [self.session invalidateAndCancel];
    }
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _taskHandlerDic = [[NSMutableDictionary alloc] init];
        _lock = [[NSRecursiveLock alloc] init];
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[BAFileDownloadThreads networkQueue]];
    }
    return self;
}

#pragma mark - public method
+ (BAFileDownloadSession *)sharedSession
{
    static dispatch_once_t onceToken;
    static BAFileDownloadSession *_sharedSession;
    dispatch_once(&onceToken, ^{
        _sharedSession = [[BAFileDownloadSession alloc] init];
    });
    return _sharedSession;
}

- (void)startDataTask:(NSMutableURLRequest *)request completionHandler:(BAFileDownloaderDataTaskFinishedBlock)completionHandler
{
    __weak typeof(self) weakSelf = self;
    [[BAFileDownloadThreads networkQueue] addOperationWithBlock:^() {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSURLSessionDataTask *sessionTask = [strongSelf.session dataTaskWithRequest:request];
        [strongSelf record:sessionTask completionHandler:completionHandler];
        [sessionTask resume];
    }];
}

- (void)startDownloadTask:(NSMutableURLRequest *)request
          progressHandler:(BAFileDownloaderDownloadTaskProgressBlock)progressHandler
        completionHandler:(BAFileDownloaderDownloadTaskFinishedBlock)completionHandler
{
    __weak typeof(self) weakSelf = self;
    [[BAFileDownloadThreads networkQueue] addOperationWithBlock:^() {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSURLSessionDownloadTask *sessionTask = [strongSelf.session downloadTaskWithRequest:request];
        [strongSelf record:sessionTask progressHandler:progressHandler];
        [strongSelf record:sessionTask completionHandler:completionHandler];
        [sessionTask resume];
    }];
}

#pragma mark - NSURLSessionTaskDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error
{
    if (error) {
        if ([task isKindOfClass:[NSURLSessionDataTask class]]) {
            BAFileDownloaderDataTaskFinishedBlock finishedBlock = [self getCompletionHandler:task];
            if (finishedBlock) {
                finishedBlock(nil, error);
            }
            [self removeRecord:task];
        } else if ([task isKindOfClass:[NSURLSessionDownloadTask class]]) {
            BAFileDownloaderDownloadTaskFinishedBlock finishedBlock = [self getCompletionHandler:task];
            if (finishedBlock) {
                finishedBlock(nil, error);
            }
            [self removeRecord:task];
        }
    }
}

#pragma mark - NSURLSessionDataDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    completionHandler(NSURLSessionResponseAllow);
    
    BAFileDownloaderDataTaskFinishedBlock finishedBlock = [self getCompletionHandler:dataTask];
    if (finishedBlock) {
        finishedBlock(response, nil);
    }
    [self removeRecord:dataTask];
}

#pragma mark - NSURLSessionDownloadDelegate
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    BAFileDownloaderDownloadTaskFinishedBlock finishedBlock = [self getCompletionHandler:downloadTask];
    if (finishedBlock) {
        finishedBlock(location, nil);
    }
    [self removeRecord:downloadTask];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    BAFileDownloaderDownloadTaskProgressBlock progressBlock = [self getProgressHandler:downloadTask];
    if (progressBlock) {
        progressBlock(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
    }
}

#pragma mark - private methods
- (NSString *)keyForProgressHandler:(NSURLSessionTask *)task
{
    return [NSString stringWithFormat:@"%ld_progressHandler", task.taskIdentifier];
}

- (NSString *)keyForCompletionHandler:(NSURLSessionTask *)task
{
    return [NSString stringWithFormat:@"%ld_completionHandler", task.taskIdentifier];
}

- (void)record:(NSURLSessionTask *)task progressHandler:(id)progressHandler
{
    if (!task || !progressHandler) {
        return;
    }
    [self.lock lock];
    [self.taskHandlerDic setObject:progressHandler forKey:[self keyForProgressHandler:task]];
    [self.lock unlock];
}

- (void)record:(NSURLSessionTask *)task completionHandler:(id)completionHandler
{
    if (!task || !completionHandler) {
        return;
    }
    [self.lock lock];
    [self.taskHandlerDic setObject:completionHandler forKey:[self keyForCompletionHandler:task]];
    [self.lock unlock];
}

- (void)removeRecord:(NSURLSessionTask *)task
{
    if (!task) {
        return;
    }
    [self.lock lock];
    [self.taskHandlerDic removeObjectForKey:[self keyForProgressHandler:task]];
    [self.taskHandlerDic removeObjectForKey:[self keyForCompletionHandler:task]];
    [self.lock unlock];
}

- (id)getProgressHandler:(NSURLSessionTask *)task
{
    if (!task) {
        return nil;
    }
    id result = nil;
    [self.lock lock];
    result = [self.taskHandlerDic objectForKey:[self keyForProgressHandler:task]];
    [self.lock unlock];
    return result;
}

- (id)getCompletionHandler:(NSURLSessionTask *)task
{
    if (!task) {
        return nil;
    }
    id result = nil;
    [self.lock lock];
    result = [self.taskHandlerDic objectForKey:[self keyForCompletionHandler:task]];
    [self.lock unlock];
    return result;
}

@end
