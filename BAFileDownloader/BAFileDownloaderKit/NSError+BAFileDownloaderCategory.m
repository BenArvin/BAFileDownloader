//
//  NSError+BAFileDownloaderCategory.m
//  BAFileDownloader
//
//  Created by nds on 2017/12/8.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "NSError+BAFileDownloaderCategory.h"

@implementation NSError (BAFileDownloaderCategory)

+ (NSError *)BAFD_simpleErrorWithDescription:(NSString *)description
{
    if (!description || description.length == 0) {
        description = @"error";
    }
    return [NSError errorWithDomain:description code:-1 userInfo:@{NSLocalizedDescriptionKey : description, NSLocalizedFailureReasonErrorKey : description}];
}

@end
