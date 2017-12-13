//
//  BAFileDownloaderSession.m
//  BAFileDownloader
//
//  Created by nds on 2017/12/6.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "BAFileDownloaderSession.h"

@interface BAFileDownloaderSession() <NSURLSessionDelegate>

@property (nonatomic) NSURLSession *session;
@property (nonatomic) NSOperationQueue *queue;

@end

@implementation BAFileDownloaderSession

- (void)dealloc
{
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _queue = [[NSOperationQueue alloc] init];
        _queue.name = @"BAFileDownloaderSessionQueue";
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:self.queue];
    }
    return self;
}

#pragma mark - public method
+ (NSURLSession *)sharedSession
{
    return [BAFileDownloaderSession sharedDownloaderSession].session;
}

#pragma mark - private method
+ (BAFileDownloaderSession *)sharedDownloaderSession
{
    static dispatch_once_t onceToken;
    static BAFileDownloaderSession *sharedDownloaderSession;
    dispatch_once(&onceToken, ^{
        sharedDownloaderSession = [[BAFileDownloaderSession alloc] init];
    });
    return sharedDownloaderSession;
}

@end
