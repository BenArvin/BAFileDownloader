//
//  BAStreamFileMD5.h
//  BAFileDownloader
//
//  Created by BenArvin on 2018/6/25.
//  Copyright © 2018年 nds. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BAStreamFileMD5: NSObject

+ (NSString *)md5:(NSString *)path;

@end
