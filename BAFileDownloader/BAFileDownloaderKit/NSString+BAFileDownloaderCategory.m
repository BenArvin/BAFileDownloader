//
//  NSString+BAFileDownloaderCategory.m
//  BAFileDownloader
//
//  Created by nds on 2017/12/1.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "NSString+BAFileDownloaderCategory.h"
#import<CommonCrypto/CommonDigest.h>

@implementation NSString (BAFileDownloaderCategory)

- (BOOL)BAFD_isValid
{
    return self.length > 0;
}

- (NSString *)BAFD_MD5
{
    if (![self BAFD_isValid]) {
        return nil;
    }
    const char *cStr = [self UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

@end
