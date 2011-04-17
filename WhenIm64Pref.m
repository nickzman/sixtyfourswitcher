//
//  WhenIm64Pref.m
//  SixtyFourSwitcher
//
//  Created by Nick Zitzmann on 1/10/09.
//  Copyright (c) 2009 Nick Zitzmann. All rights reserved.
//
/*
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 •	Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 •	Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 •	Neither the name of Nick Zitzmann nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "WhenIm64Pref.h"
#import <sys/types.h>
#import <sys/sysctl.h>

@interface WhenIm64Pref (Internal)
- (BOOL)cpuSupports64Bit;
- (BOOL)kernelHas32BitVersion;
- (BOOL)kernelHas64BitVersion;
- (BOOL)isComputerProbablySupportedBy64BitKernel;
- (BOOL)isRunning64Bit;
- (NSDictionary *)nvram;
- (NSData *)outputOfTaskWithLaunchPath:(NSString *)launchPath arguments:(NSArray *)arguments;
- (BOOL)userHasRequiredCommandLineToolsInstalled;
- (BOOL)willBoot64Bit;
@end

@implementation WhenIm64Pref

- (void)mainViewDidLoad
{
	AuthorizationItem item[] = {/*{"system.preferences", 0L, NULL, 0}, */{"system.privilege.admin", 0L, NULL, 0}};
	AuthorizationRights rights = {sizeof(*item)/sizeof(item), item};
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	
	[_versionTxt setStringValue:[[bundle infoDictionary] objectForKey:@"CFBundleVersion"]];
	[_copyrightTxt setStringValue:[[bundle localizedInfoDictionary] objectForKey:@"NSHumanReadableCopyright"]];
	
	// Check to see if our required Foundation stuff is installed:
	if ([self userHasRequiredCommandLineToolsInstalled] == NO)
	{
		NSBeginAlertSheet(NSLocalizedStringFromTableInBundle(@"Sorry, but a required tool was not found.", @"WhenIm64Pref", bundle, @"Required tool not found sheet title"), nil, nil, nil, [[self mainView] window], nil, nil, nil, NULL, NSLocalizedStringFromTableInBundle(@"This preference pane requires the following command line tools: /usr/bin/lipo and /usr/sbin/nvram. Since your computer is missing one of these tools for some reason, this pane cannot do anything.", @"WhenIm64Pref", bundle, @"Required tool not found sheet body"));
		[_switcherMatrix setEnabled:NO];
		[_rebootButton setEnabled:NO];
		[_authorizationView setEnabled:NO];
		return;
	}
	
	// Set up authorization:
	[_authorizationView setAuthorizationRights:&rights];
	[_authorizationView setDelegate:self];
	[_authorizationView updateStatus:nil];	// this triggers the delegate if we're authorized
	[_authorizationView setAutoupdate:YES];
	
	// Check to see if the user is already booting the 64-bit kernel:
	if ([self willBoot64Bit])
	{
		[_switcherMatrix selectCellAtRow:1 column:0];
		[[_switcherMatrix cellAtRow:0 column:0] setState:NSOffState];	// believe it or not, we have to do this manually or else the UI will be wrong
	}
	else
		[_switcherMatrix selectCellAtRow:0 column:0];
}


- (IBAction)switchCPUArchitecture:(id)sender
{
	if ([[NSProcessInfo processInfo] respondsToSelector:@selector(disableSuddenTermination)])	// in the extremely unlikely event that the user wants to log out and switch architectures at the same time, then don't allow that, since that would be bad
		[[NSProcessInfo processInfo] performSelector:@selector(disableSuddenTermination)];
	
	BOOL userWantsToBoot64Bit = ([_switcherMatrix selectedRow] == 1);
	BOOL userIsBooting64Bit = [self willBoot64Bit];
	
	if (userWantsToBoot64Bit != userIsBooting64Bit)
	{
		SFAuthorization *authorization = [_authorizationView authorization];
		int childPID;
		OSStatus err;
		
		if (userWantsToBoot64Bit)
		{
			char * const addX8664BootArgs[] = {"boot-args=arch=x86_64", NULL};	// yeah, only the shell has to put quotation marks around the arch=xxxx part
			
			err = AuthorizationExecuteWithPrivileges([authorization authorizationRef], "/usr/sbin/nvram", kAuthorizationFlagDefaults, addX8664BootArgs, NULL);
		}
		else
		{
			char * const addI386BootArgs[] = {"boot-args=arch=i386", NULL};
			
			err = AuthorizationExecuteWithPrivileges([authorization authorizationRef], "/usr/sbin/nvram", kAuthorizationFlagDefaults, addI386BootArgs, NULL);
		}
		wait(&childPID);	// bring out your dead!
		if (err == noErr)
		{
			[_rebootWarningTxt setHidden:NO];
			// If the user previously used systemsetup or some third-party startup selector that modifies the boot plist, then that will conflict with our work.
			// So if systemsetup is present, let's use it to set this back to its default value in order to remove the conflict...
			if ([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/sbin/systemsetup"])
			{
				char * const defaultKernelBootArchArgs[] = {"-setkernelbootarchitecture", "default", NULL};
				
				err = AuthorizationExecuteWithPrivileges([authorization authorizationRef], "/usr/sbin/systemsetup", kAuthorizationFlagDefaults, defaultKernelBootArchArgs, NULL);
				wait(&childPID);
			}
		}
		else	// if there was a problem, then reset the radio back to the way it was
		{
			[[NSRunLoop currentRunLoop] performSelector:@selector(switchBack:) target:self argument:[NSNumber numberWithInteger:(userWantsToBoot64Bit ? 0 : 1)] order:0 modes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];
			//[_switcherMatrix selectCellAtRow:(userWantsToBoot64Bit ? 0 : 1) column:0];
		}
	}
	if ([[NSProcessInfo processInfo] respondsToSelector:@selector(enableSuddenTermination)])	// ok, turn it back on
		[[NSProcessInfo processInfo] performSelector:@selector(enableSuddenTermination)];
}


- (void)switchBack:(NSNumber *)switchBackRow
{
	[_switcherMatrix selectCellAtRow:[switchBackRow integerValue] column:0];
}


- (IBAction)reboot:(id)sender
{
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSString *localizedWillReboot64BitString = NSLocalizedStringFromTableInBundle(@"Your computer will use the 64-bit version of the kernel after restarting.", @"WhenIm64Pref", bundle, @"Restart description/64-bit");
	NSString *localizedWillReboot32BitString = NSLocalizedStringFromTableInBundle(@"Your computer will use the 32-bit version of the kernel after restarting.", @"WhenIm64Pref", bundle, @"Restart description/32-bit");
	
	if (NSRunAlertPanel(NSLocalizedStringFromTableInBundle(@"Are you sure you want to restart your computer?", @"WhenIm64Pref", bundle, @"Are you sure title"), ([self willBoot64Bit] ? localizedWillReboot64BitString : localizedWillReboot32BitString), NSLocalizedStringFromTableInBundle(@"Restart", @"WhenIm64Pref", bundle, @"Restart"), NSLocalizedStringFromTableInBundle(@"Cancel", @"WhenIm64Pref", bundle, @"Cancel"), nil) == NSAlertDefaultReturn)
	{
		NSAppleScript *rebootScript = [[NSAppleScript alloc] initWithSource:@"tell application \"System Events\" to restart"];
	
		[rebootScript executeAndReturnError:NULL];
		[rebootScript release];	// we're probably going to go bye bye soon, but just in case some other app blocked our attempt...
	}
}


#pragma mark -


- (void)authorizationViewDidAuthorize:(SFAuthorizationView *)view
{
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	
	[_switcherMatrix setEnabled:YES];
	if (![self kernelHas32BitVersion])
		[[_switcherMatrix cellAtRow:0 column:0] setEnabled:NO];
	
	if (![self cpuSupports64Bit])
	{
		[_rebootWarningTxt setStringValue:NSLocalizedStringFromTableInBundle(@"Your computer\\U2019s CPU does not support 64-bit addressing.", @"WhenIm64Pref", bundle, @"Not supported because the Mac has a 32-bit CPU")];
		[_rebootWarningTxt setHidden:NO];
		[[_switcherMatrix cellAtRow:1 column:0] setEnabled:NO];
	}
	else if (![self kernelHas64BitVersion])
	{
		SInt32 osVersion;
		
		Gestalt(gestaltSystemVersion, &osVersion);
		if (osVersion < 0x1060)
			[_rebootWarningTxt setStringValue:NSLocalizedStringFromTableInBundle(@"Sorry, but this preference pane requires Snow Leopard or later.", @"WhenIm64Pref", bundle, @"Not supported because Leopard didn't have a 64-bit kernel")];
		else
			[_rebootWarningTxt setStringValue:NSLocalizedStringFromTableInBundle(@"For some reason, your OS install lacks a 64-bit kernel. Try reinstalling the OS.", @"WhenIm64Pref", bundle, @"Not supported because the 64-bit kernel wasn't found")];
		[_rebootWarningTxt setHidden:NO];
		[[_switcherMatrix cellAtRow:1 column:0] setEnabled:NO];
	}
	else if (![self isComputerProbablySupportedBy64BitKernel])
	{
		[_rebootWarningTxt setStringValue:NSLocalizedStringFromTableInBundle(@"Your Mac model has a 64-bit CPU, but it does not support booting the 64-bit kernel.", @"WhenIm64Pref", bundle, @"Not supported because the computer isn't on the whitelist")];
		[_rebootWarningTxt setHidden:NO];
		[[_switcherMatrix cellAtRow:1 column:0] setEnabled:NO];
	}
}


- (void)authorizationViewDidDeauthorize:(SFAuthorizationView *)view;
{
	[_switcherMatrix setEnabled:NO];
}

@end

@implementation WhenIm64Pref (Internal)

- (BOOL)cpuSupports64Bit
{
	size_t len = sizeof(int);
	int results;
	
	if (sysctlbyname("hw.cpu64bit_capable", &results, &len, NULL, 0L) == 0)
		return (results != 0);
	return NO;
}


- (BOOL)kernelHas32BitVersion
{
	NSData *results = [self outputOfTaskWithLaunchPath:@"/usr/bin/lipo" arguments:[NSArray arrayWithObjects:@"-info", @"/mach_kernel", nil]];
	NSString *resultsStr = [[[NSString alloc] initWithData:results encoding:NSUTF8StringEncoding] autorelease];
	
	if (resultsStr && [resultsStr rangeOfString:@"i386"].location != NSNotFound)
		return YES;
	return NO;
}


- (BOOL)kernelHas64BitVersion
{
	NSData *results = [self outputOfTaskWithLaunchPath:@"/usr/bin/lipo" arguments:[NSArray arrayWithObjects:@"-info", @"/mach_kernel", nil]];
	NSString *resultsStr = [[[NSString alloc] initWithData:results encoding:NSUTF8StringEncoding] autorelease];
	
	if (resultsStr && [resultsStr rangeOfString:@"x86_64"].location != NSNotFound)
		return YES;
	return NO;
}


- (BOOL)isComputerProbablySupportedBy64BitKernel
{
	size_t len;
	char *results;
	
	if (sysctlbyname("hw.model", NULL, &len, NULL, 0L) == 0)
	{
		results = malloc(len*sizeof(char));
		if (sysctlbyname("hw.model", results, &len, NULL, 0L) == 0)
		{
			NSString *hwModel = [NSString stringWithCString:results encoding:NSASCIIStringEncoding];
			
			// Here's how we're going to do this:
			// Apple doesn't support booting the 64-bit kernel on their non-pro computers, and also doesn't support booting it on some older computers.
			// So we look for the 64-bit-capable computers that Apple says doesn't work, and return NO for them.
			// If it's not on the list, then return YES.
			// There are a number of 32-bit-only Macs for which this method will return YES, so don't rely on this method entirely...
			
			if ([hwModel hasPrefix:@"Macmini"])	// Mac minis are supported from the 4th generation onwards
			{
				if ([hwModel hasSuffix:@"1,1"] || [hwModel hasSuffix:@"2,1"] || [hwModel hasSuffix:@"3,1"])
					return NO;
			}
			else if ([hwModel hasPrefix:@"MacBook"])
			{
				if ([hwModel rangeOfString:@"MacBookPro"].location == NSNotFound)	// non-Pro MacBooks aren't supported
					return NO;
				else if ([hwModel hasSuffix:@"2,1"] || [hwModel hasSuffix:@"2,2"] || [hwModel hasSuffix:@"3,1"])	// the second and third edition MBPs aren't supported
					return NO;
			}
			else if ([hwModel hasPrefix:@"iMac"])	// certain older iMac models aren't supported
			{
				if ([hwModel hasSuffix:@"5,1"] || [hwModel hasSuffix:@"5,2"] || [hwModel hasSuffix:@"6,1"] || [hwModel hasSuffix:@"7,1"])
					return NO;
			}
			else if ([hwModel hasPrefix:@"MacPro"])	// the first two Pro models aren't supported
			{
				if ([hwModel hasSuffix:@"1,1"] || [hwModel hasSuffix:@"2,1"])
					return NO;
			}
			else if ([hwModel hasPrefix:@"Xserve"])	// the very first Intel-based Xserve supposedly isn't supported
			{
				if ([hwModel hasSuffix:@"1,1"])
					return NO;
			}
			
			free(results);
			return YES;
		}
		free(results);
	}
	return NO;
}


- (BOOL)isRunning64Bit
{
	size_t len;
	char *results;
	
	if (sysctlbyname("hw.machine", NULL, &len, NULL, 0L) == 0)
	{
		results = malloc(len*sizeof(char));
		if (sysctlbyname("hw.machine", results, &len, NULL, 0L) == 0)
		{
			if (strncmp("x86_64", results, 6) == 0)	// if true, then the kernel is currently 64-bit
			{
				free(results);
				return YES;
			}
		}
		free(results);
	}
	return NO;
}


- (NSDictionary *)nvram
{
	NSData *results = [self outputOfTaskWithLaunchPath:@"/usr/sbin/nvram" arguments:[NSArray arrayWithObject:@"-xp"]];
	NSDictionary *returnValue;
	NSError *err = nil;
	
	returnValue = [NSPropertyListSerialization propertyListWithData:results options:NSPropertyListImmutable format:NULL error:&err];
	if (returnValue == nil && err)
		NSLog(@"Couldn't read nvram property list (64-bit): %@", err);
	return returnValue;
}


- (NSData *)outputOfTaskWithLaunchPath:(NSString *)launchPath arguments:(NSArray *)arguments
{
	NSPipe *pipe = [NSPipe pipe];
	NSTask *task = [[[NSTask alloc] init] autorelease];
	NSData *output;
	
	NSAssert(pipe, @"Looks like we're out of pipes. Oh no!");
	
	[task setLaunchPath:launchPath];
	[task setArguments:arguments];
	[task setStandardOutput:pipe];
	[task launch];
	output = [[pipe fileHandleForReading] readDataToEndOfFile];
	[task waitUntilExit];
	
	return output;
}


- (BOOL)userHasRequiredCommandLineToolsInstalled
{
	if ([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/lipo"] == NO)
		return NO;
	else if ([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/sbin/nvram"] == NO)
		return NO;
	return YES;
}


- (BOOL)willBoot64Bit
{
	NSDictionary *nvram = [self nvram];
	
	// First, check com.apple.Boot. In Snow Leopard, this plist trumps NVRAM settings.
	if ([[NSFileManager defaultManager] fileExistsAtPath:@"/Library/Preferences/SystemConfiguration/com.apple.Boot.plist"])
	{
		NSDictionary *bootDict = [NSDictionary dictionaryWithContentsOfFile:@"/Library/Preferences/SystemConfiguration/com.apple.Boot.plist"];
		
		if ([[bootDict objectForKey:@"Kernel Architecture"] isEqualToString:@"x86_64"])
			return YES;
		else if ([[bootDict objectForKey:@"Kernel Architecture"] isEqualToString:@"i386"])
			return NO;
	}
	// Then, check the NVRAM to see if this setting is different from the computer's default:
	if ([nvram objectForKey:@"boot-args"])
	{
		if ([[nvram objectForKey:@"boot-args"] rangeOfString:@"arch=i386"].location != NSNotFound)
			return NO;
		else if ([[nvram objectForKey:@"boot-args"] rangeOfString:@"arch=x86_64"].location != NSNotFound)
			return YES;
	}
	// If the setting is not set, then we can only assume that the kernel is in its default architecture, so query that for our answer on whether or not this computer will boot as 64-bit.
	// (Yes, this can be fooled by the 6 and 4, or 3 and 2, keys, at startup. But AFAIK there's no way to check for that...)
	return [self isRunning64Bit];
}

@end
