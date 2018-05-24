//
//  BAFileDownloader.m
//  BAFileDownloader
//
//  Created by nds on 2017/11/30.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "BAFileDownloader.h"
#import "BAFileDownloadTask.h"
#import "BAFileDownloadOperation.h"
#import "NSString+BAFileDownloaderCategory.h"
#import "BAFileDownloaderThreads.h"

@interface BAFileDownloader()<BAFileDownloadOperationDelegate>

@property (nonatomic) NSMutableDictionary <NSString *, BAFileDownloadOperation *> *operationsDic;//key:URL(MD5), value:downloadOperation

@end

@implementation BAFileDownloader

- (instancetype)init
{
    self = [super init];
    if (self) {
        _operationsDic = [[NSMutableDictionary alloc] init];
    }
    return self;
}

#pragma mark - public method
+ (void)addTask:(BAFileDownloadTask *)task
{
    [[BAFileDownloader sharedDownloader] addTask:task];
}

+ (void)removeTask:(BAFileDownloadTask *)task
{
    [[BAFileDownloader sharedDownloader] removeTask:task];
}

+ (void)startTasksWithURL:(NSString *)URL
{
    [[BAFileDownloader sharedDownloader] startTasksWithURL:URL];
}

+ (void)pauseTasksWithURL:(NSString *)URL
{
    [[BAFileDownloader sharedDownloader] pauseTasksWithURL:URL];
}

#pragma private method
+ (BAFileDownloader *)sharedDownloader
{
    static dispatch_once_t onceToken;
    static BAFileDownloader *sharedDownloader;
    dispatch_once(&onceToken, ^{
        sharedDownloader = [[BAFileDownloader alloc] init];
    });
    return sharedDownloader;
}

- (void)addTask:(BAFileDownloadTask *)task
{
    __weak typeof(self) weakSelf = self;
    [[BAFileDownloaderThreads actionQueue] addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!task || ![task.URL BAFD_isValid]) {
            return;
        }
        NSString *key = [task.URL BAFD_MD5];
        BAFileDownloadOperation *operation = [strongSelf.operationsDic objectForKey:key];
        if (!operation) {
            operation = [[BAFileDownloadOperation alloc] init];
            operation.delegate = self;
            [strongSelf.operationsDic setObject:operation forKey:key];
        }
        [operation addTask:task];
    }];
}

- (void)removeTask:(BAFileDownloadTask *)task
{
    __weak typeof(self) weakSelf = self;
    [[BAFileDownloaderThreads actionQueue] addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!task || ![task.URL BAFD_isValid]) {
            return;
        }
        NSString *key = [task.URL BAFD_MD5];
        BAFileDownloadOperation *operation = [strongSelf.operationsDic objectForKey:key];
        [operation removeTask:task];
    }];
}

- (void)startTasksWithURL:(NSString *)URL
{
    __weak typeof(self) weakSelf = self;
    [[BAFileDownloaderThreads actionQueue] addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![URL BAFD_isValid]) {
            return;
        }
        NSString *key = [URL BAFD_MD5];
        BAFileDownloadOperation *operation = [strongSelf.operationsDic objectForKey:key];
        [operation start];
    }];
}

- (void)pauseTasksWithURL:(NSString *)URL
{
    __weak typeof(self) weakSelf = self;
    [[BAFileDownloaderThreads actionQueue] addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (![URL BAFD_isValid]) {
            return;
        }
        NSString *key = [URL BAFD_MD5];
        BAFileDownloadOperation *operation = [strongSelf.operationsDic objectForKey:key];
        [operation pause];
    }];
}

#pragma mark - BAFileDownloadOperationDelegate
- (void)fileDownloadOperation:(BAFileDownloadOperation *)operation finished:(NSError *)error
{
    __weak typeof(self) weakSelf = self;
    [[BAFileDownloaderThreads actionQueue] addOperationWithBlock:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf.operationsDic removeObjectForKey:[operation.URL BAFD_MD5]];
    }];
}

@end
