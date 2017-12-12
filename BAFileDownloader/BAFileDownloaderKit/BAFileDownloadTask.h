//
//  BAFileDownloadTask.h
//  BAFileDownloader
//
//  Created by nds on 2017/11/30.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef void (^BAFileDownloadStartedBlock)(NSURL *URL);
typedef void (^BAFileDownloadPausedBlock)(NSURL *URL);
typedef void (^BAFileDownloadResumedBlock)(NSURL *URL);
typedef void (^BAFileDownloadFinishedBlock)(NSURL *URL, NSError *error);
typedef void (^BAFileDownloadProgressBlock)(NSURL *URL, CGFloat progress);

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
