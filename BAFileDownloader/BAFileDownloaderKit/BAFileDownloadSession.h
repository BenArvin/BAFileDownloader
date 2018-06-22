//
//  BAFileDownloadSession.h
//  BAFileDownloader
//
//  Created by nds on 2017/12/6.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^BAFileDownloaderDataTaskFinishedBlock)(NSURLResponse *response, NSError *error);
typedef void(^BAFileDownloaderDownloadTaskFinishedBlock)(NSURL *location, NSError *error);
typedef void(^BAFileDownloaderDownloadTaskProgressBlock)(NSUInteger finished, NSUInteger totalFinished, NSUInteger totalExpected);

@interface BAFileDownloadSession : NSObject

+ (BAFileDownloadSession *)sharedSession;

- (void)startDataTask:(NSMutableURLRequest *)request completionHandler:(BAFileDownloaderDataTaskFinishedBlock)completionHandler;
- (void)startDownloadTask:(NSMutableURLRequest *)request
          progressHandler:(BAFileDownloaderDownloadTaskProgressBlock)progressHandler
        completionHandler:(BAFileDownloaderDownloadTaskFinishedBlock)completionHandler;

@end
