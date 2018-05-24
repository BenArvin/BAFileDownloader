//
//  BAFileDownloaderSession.m
//  BAFileDownloader
//
//  Created by nds on 2017/12/6.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "BAFileDownloaderSession.h"
#import "BAFileDownloaderThreads.h"

@interface BAFileDownloaderSession() <NSURLSessionDelegate>

@property (nonatomic) NSURLSession *session;

@end

@implementation BAFileDownloaderSession

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
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[BAFileDownloaderThreads networkQueue]];
    }
    return self;
}

#pragma mark - public method
+ (BAFileDownloaderSession *)sharedSession
{
    static dispatch_once_t onceToken;
    static BAFileDownloaderSession *_sharedSession;
    dispatch_once(&onceToken, ^{
        _sharedSession = [[BAFileDownloaderSession alloc] init];
    });
    return _sharedSession;
}

- (void)startDataTask:(NSMutableURLRequest *)request completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler
{
    __weak typeof(self) weakSelf = self;
    [[BAFileDownloaderThreads networkQueue] addOperationWithBlock:^() {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSURLSessionDataTask *sessionTask = [strongSelf.session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (completionHandler) {
                completionHandler(data, response, error);
            }
        }];
        [sessionTask resume];
    }];
}

- (void)startDownloadTask:(NSMutableURLRequest *)request completionHandler:(void (^)(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler
{
    __weak typeof(self) weakSelf = self;
    [[BAFileDownloaderThreads networkQueue] addOperationWithBlock:^() {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        NSURLSessionDownloadTask *sessionTask = [strongSelf.session downloadTaskWithRequest:request completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            if (completionHandler) {
                completionHandler(location, response, error);
            }
        }];
        [sessionTask resume];
    }];
}

@end
