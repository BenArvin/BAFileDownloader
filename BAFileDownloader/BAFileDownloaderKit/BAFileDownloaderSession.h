//
//  BAFileDownloaderSession.h
//  BAFileDownloader
//
//  Created by nds on 2017/12/6.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BAFileDownloaderSession : NSObject

+ (BAFileDownloaderSession *)sharedSession;

- (void)startDataTask:(NSMutableURLRequest *)request completionHandler:(void (^)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;
- (void)startDownloadTask:(NSMutableURLRequest *)request completionHandler:(void (^)(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error))completionHandler;

@end
