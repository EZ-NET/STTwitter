//
//  STTwitterAPIDelegate.h
//  STTwitterDemoOSX
//
//  Created by Tomohiro Kumagai on H27/08/15.
//  Copyright © 平成27年 Nicolas Seriot. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "STTwitterAPI.h"

@class STTwitterAPI;
@class ACAccountStore;

@protocol STTwitterAPIDelegate <NSObject>

@optional

- (void)twitterAPI:(STTwitterAPI*)api OSAccountStoreDidChange:(ACAccountStore*)accountStore;

@end