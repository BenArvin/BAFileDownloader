//
//  NSError+BAFileDownloaderCategory.h
//  BAFileDownloader
//
//  Created by nds on 2017/12/8.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSError (BAFileDownloaderCategory)

/**
 creat simple NSError instance

 @param description default value = error
 @return error code = -1, 
 */
+ (NSError *)BAFD_simpleErrorWithDescription:(NSString *)description;

@end
