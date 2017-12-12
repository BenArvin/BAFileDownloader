//
//  ViewController.m
//  BAFileDownloader
//
//  Created by nds on 2017/11/30.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "ViewController.h"
#import "BAFileDownloaderKit.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    BAFileDownloadTask *task = [[BAFileDownloadTask alloc] init];
//    task.URL = @"https://codeload.github.com/mpv-player/mpv/zip/master";
    task.URL = @"http://zkres.myzaker.com/img_upload/editor/article_video/2016/10/27/14775491454394.mp4";
    task.inFragmentMode = YES;
    
    [BAFileDownloader addTask:task];
    [BAFileDownloader startTasksWithURL:task.URL];
}


@end
