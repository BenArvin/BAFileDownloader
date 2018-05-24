//
//  BAFileDownloaderThreads.h
//  BAFileDownloader
//
//  Created by BenArvin on 2018/5/21.
//  Copyright © 2018年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BAFileDownloaderThreads: NSObject

+ (NSOperationQueue *)actionQueue;
+ (NSOperationQueue *)networkQueue;
+ (NSOperationQueue *)outputQueue;

@end
