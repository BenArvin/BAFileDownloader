//
//  BAFileDownloader.h
//  BAFileDownloader
//
//  Created by nds on 2017/11/30.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

@class BAFileDownloadTask;

@interface BAFileDownloader : NSObject

+ (void)addTask:(BAFileDownloadTask *)task;
+ (void)removeTask:(BAFileDownloadTask *)task;

+ (void)startTasksWithURL:(NSString *)URL;
//+ (void)pauseTasksWithURL:(NSString *)URL;

@end
