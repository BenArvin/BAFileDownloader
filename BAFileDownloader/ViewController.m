//
//  ViewController.m
//  BAFileDownloader
//
//  Created by nds on 2017/11/30.
//  Copyright © 2017年 nds. All rights reserved.
//

#import "ViewController.h"
#import "BAFileDownloaderKit.h"

@interface ViewController () <NSStreamDelegate>

@property (nonatomic) UIButton *startButton;

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
    
    self.startButton = [[UIButton alloc] init];
    [self.startButton setTitle:@"start" forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor grayColor] forState:UIControlStateHighlighted];
    [self.startButton setBackgroundColor:[UIColor lightGrayColor]];
    [self.startButton addTarget:self action:@selector(startButtonAction) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startButton];
    self.startButton.frame = CGRectMake(100, 200, 50, 40);
}

- (void)startButtonAction
{
    BAFileDownloadTask *task = [[BAFileDownloadTask alloc] init];
//    task.URL = @"http://sqdownb.onlinedown.net/down/WinRAR560.rar";
    task.fragmentSize = 1000 * 10;
//    task.URL = @"http://speed.myzone.cn/pc_elive_1.1.rar";
    task.URL = @"http://zkres.myzaker.com/img_upload/editor/article_video/2016/10/27/14775491454394.mp4";
    task.inFragmentMode = YES;
    task.progressBlock = ^(NSString *URL, NSUInteger finished, NSUInteger expected) {
        NSLog(@"-----------  %ld %ld %f", finished, expected, (CGFloat)finished / (CGFloat)expected);
    };
    task.finishedBlock = ^(NSString *URL, NSString *filePath, NSError *error) {
        NSLog(@"-----------  download finished");
    };

    [BAFileDownloader addTask:task];
    [BAFileDownloader startTasksWithURL:task.URL];
}

@end
