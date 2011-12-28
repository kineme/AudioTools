#import "AudioFileInfoPatch.h"

@implementation AudioFileInfoPatch : QCPatch

+ (QCPatchExecutionMode)executionModeWithIdentifier:(id)fp8
{
	return kQCPatchExecutionModeProcessor;
}
+ (BOOL)allowsSubpatchesWithIdentifier:(id)fp8
{
	return NO;
}
+ (QCPatchTimeMode)timeModeWithIdentifier:(id)fp8
{
	return kQCPatchTimeModeNone;
}

- (id)initWithIdentifier:(id)fp8
{
	if(self=[super initWithIdentifier:fp8])
	{
		[[self userInfo] setObject: @"Kineme Audio File Info" forKey: @"name"];
	}
	
	return self;
}

- (BOOL)execute:(QCOpenGLContext *)context time:(double)time arguments:(NSDictionary *)arguments
{
	if( [inputPath wasUpdated] )
	{
		NSString *path = KIExpandPath(self,[inputPath stringValue]);
		NSSound *s = [[NSSound alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] byReference:YES];

		if(!s)
		{
			NSLog(@"didn't load");
			[outputFileLoaded setBooleanValue:NO];
			[outputDuration setDoubleValue:0.0];
			return YES;
		}

		[outputFileLoaded setBooleanValue:YES];
		[outputDuration setDoubleValue:[s duration]];

		[s release];
	}

	return YES;
}

@end
