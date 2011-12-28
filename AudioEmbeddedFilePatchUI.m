#import "AudioEmbeddedFilePatchUI.h"

@interface NSObject (WarningSuppression)
-(void)importData:(NSString*)filename;
@end


@implementation AudioEmbeddedFilePatchUI

/* This method returns the NIB file to use for the inspector panel */
+(NSString*)viewNibName
{
    return @"AudioEmbeddedFilePatchUI";
}

/* This method specifies the title for the patch */
// FIXME:  is this used on Leopard, or is it Tiger-only?
+(NSString*)viewTitle
{
    return @"Audio Embedded File Player";
}

-(IBAction)loadData:(id)sender
{
	//NSLog(@"loadData:%@", sender);
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setExtensionHidden: NO];
	[openPanel setTreatsFilePackagesAsDirectories:NO];
	[openPanel setCanSelectHiddenExtension: NO];
	[openPanel setCanChooseDirectories: NO];
	[openPanel setAllowsMultipleSelection: NO];
	[openPanel setAllowsOtherFileTypes: NO];
	[openPanel setDelegate: self];
	if([openPanel runModal] == NSFileHandlingPanelOKButton)
		[[self patch] importData: [[openPanel filenames] objectAtIndex: 0]];
}

// used with open panel, to disallow selection of non-plist types
- (BOOL)panel:(id)sender shouldShowFilename:(NSString *)filename
{
	// if it's an audio file, it's good
	CFStringRef itemUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)[filename pathExtension], NULL);
	if(UTTypeConformsTo(itemUTI, kUTTypeAudio))
	{
		CFRelease(itemUTI);
		return YES;
	}
	CFRelease(itemUTI);
	// if it's a directory, it's good
	// FIXME: actually it's not -- bundles need to get excluded (they're selectable currently...)
	NSDictionary *attrs = [[NSFileManager defaultManager] fileAttributesAtPath: filename traverseLink: YES];
	if([attrs fileType] == NSFileTypeDirectory)
		return YES;
	return NO;
}


@end
