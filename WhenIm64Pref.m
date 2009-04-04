//
//  WhenIm64Pref.m
//  SixtyFourSwitcher
//
//  Created by Nick Zitzmann on 1/10/09.
//  Copyright (c) 2009 Nick Zitzmann. All rights reserved.
//

#import "WhenIm64Pref.h"
#import <sys/types.h>
#import <sys/sysctl.h>

@interface WhenIm64Pref (Internal)
- (BOOL)cpuCanBoot64Bit;
- (BOOL)kernelHas32BitVersion;
- (BOOL)kernelHas64BitVersion;
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
			[_rebootWarningTxt setHidden:NO];
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
	[_switcherMatrix setEnabled:YES];
	if ([self kernelHas32BitVersion] == NO)
		[[_switcherMatrix cellAtRow:0 column:0] setEnabled:NO];
	if ([self cpuCanBoot64Bit] == NO || [self kernelHas64BitVersion] == NO)
		[[_switcherMatrix cellAtRow:1 column:0] setEnabled:NO];
}


- (void)authorizationViewDidDeauthorize:(SFAuthorizationView *)view;
{
	[_switcherMatrix setEnabled:NO];
}

@end

@implementation WhenIm64Pref (Internal)

- (BOOL)cpuCanBoot64Bit
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
	
#ifdef __LP64__
	NSError *err = nil;
	
	returnValue = [NSPropertyListSerialization propertyListWithData:results options:NSPropertyListImmutable format:NULL error:&err];
	if (returnValue == nil && err)
		NSLog(@"Couldn't read nvram property list (64-bit): %@", err);
#else
	NSString *err = nil;
	
	returnValue = [NSPropertyListSerialization propertyListFromData:results mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&err];
	if (returnValue == nil && err)
	{
		NSLog(@"Couldn't read nvram property list (32-bit): %@", err);
		[err release];	// the documentation says we have to do this, oddly enough
	}
#endif
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
	
	// First, check the NVRAM to see if this setting is different from the computer's default:
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
