//
//  WhenIm64Pref.h
//  WhenIm64
//
//  Created by Nick Zitzmann on 1/10/09.
//  Copyright (c) 2009 __MyCompanyName__. All rights reserved.
//

#import <PreferencePanes/PreferencePanes.h>
#import <SecurityInterface/SFAuthorizationView.h>

@interface WhenIm64Pref : NSPreferencePane 
{
	IBOutlet NSMatrix *_switcherMatrix;
	IBOutlet NSTextField *_rebootWarningTxt;
	IBOutlet NSButton *_rebootButton;
	IBOutlet SFAuthorizationView *_authorizationView;
	IBOutlet NSTextField *_versionTxt;
	IBOutlet NSTextField *_copyrightTxt;
}

- (IBAction)switchCPUArchitecture:(id)sender;
- (IBAction)reboot:(id)sender;

@end
