//
//  NSString+BAFileDownloaderCategory.h
//  BAFileDownloader
//
//  Created by nds on 2017/12/1.
//  Copyright © 2017年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (BAFileDownloaderCategory)

- (BOOL)BAFD_isValid;
- (NSString *)BAFD_MD5;

@end
