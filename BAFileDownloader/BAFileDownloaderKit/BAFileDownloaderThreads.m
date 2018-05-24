//
//  BAFileDownloaderThreads.m
//  BAFileDownloader
//
//  Created by BenArvin on 2018/5/21.
//  Copyright © 2018年 nds. All rights reserved.
//

#import "BAFileDownloaderThreads.h"

@implementation BAFileDownloaderThreads

+ (NSOperationQueue *)actionQueue
{
    static dispatch_once_t onceToken;
    static NSOperationQueue *_actionQueue;
    dispatch_once(&onceToken, ^{
        _actionQueue = [[NSOperationQueue alloc] init];
        _actionQueue.maxConcurrentOperationCount = 1;
        [_actionQueue setName:@"com.BAFileDownloader.actionQueue"];
    });
    return _actionQueue;
}

+ (NSOperationQueue *)networkQueue
{
    static dispatch_once_t onceToken;
    static NSOperationQueue *_networkQueue;
    dispatch_once(&onceToken, ^{
        _networkQueue = [[NSOperationQueue alloc] init];
        _networkQueue.maxConcurrentOperationCount = 5;
        [_networkQueue setName:@"com.BAFileDownloader.networkQueue"];
    });
    return _networkQueue;
}

+ (NSOperationQueue *)outputQueue
{
    static dispatch_once_t onceToken;
    static NSOperationQueue *_outputQueue;
    dispatch_once(&onceToken, ^{
        _outputQueue = [[NSOperationQueue alloc] init];
        [_outputQueue setName:@"com.BAFileDownloader.outputQueue"];
    });
    return _outputQueue;
}

@end
