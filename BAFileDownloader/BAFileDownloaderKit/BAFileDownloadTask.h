//
//  BAFileDownloadTask.h
//  BAFileDownloader
//
//  Created by nds on 2017/11/30.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef void (^BAFileDownloadStartedBlock)(NSString *URL);
typedef void (^BAFileDownloadPausedBlock)(NSString *URL);
typedef void (^BAFileDownloadResumedBlock)(NSString *URL);
typedef void (^BAFileDownloadFinishedBlock)(NSString *URL, NSString *filePath, NSError *error);
typedef void (^BAFileDownloadProgressBlock)(NSString *URL, NSUInteger finished, NSUInteger expected);

@interface BAFileDownloadTask : NSObject

@property (nonatomic, copy) NSString *URL;
@property (nonatomic, copy) NSString *fileMD5;
@property (nonatomic, assign) BOOL inFragmentMode;//default YES
@property (nonatomic, assign) NSUInteger fragmentSize;//default 1024*10 Byte


@property (nonatomic, copy) BAFileDownloadStartedBlock startedBlock;
@property (nonatomic, copy) BAFileDownloadPausedBlock pausedBlock;
@property (nonatomic, copy) BAFileDownloadResumedBlock resumedBlock;
@property (nonatomic, copy) BAFileDownloadFinishedBlock finishedBlock;

@property (nonatomic, copy) BAFileDownloadProgressBlock progressBlock;

@end
