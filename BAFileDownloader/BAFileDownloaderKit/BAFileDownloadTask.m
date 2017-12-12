//
//  BAFileDownloadTask.m
//  BAFileDownloader
//
//  Created by nds on 2017/11/30.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "BAFileDownloadTask.h"

@interface BAFileDownloadTask()
@end

@implementation BAFileDownloadTask

- (instancetype)init
{
    self =  [super init];
    if (self) {
        self.inFragmentMode = YES;
        self.fragmentSize = 1024 * 10;
    }
    return self;
}

@end
