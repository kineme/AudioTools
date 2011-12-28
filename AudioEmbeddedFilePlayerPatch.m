#import "AudioEmbeddedFilePlayerPatch.h"
#import "AudioEmbeddedFilePatchUI.h"


@implementation AudioEmbeddedFilePlayerPatch : QCPatch

+ (QCPatchExecutionMode)executionModeWithIdentifier:(id)fp8
{
	return kQCPatchExecutionModeConsumer;
}
+ (BOOL)allowsSubpatchesWithIdentifier:(id)fp8
{
	return NO;
}
+ (QCPatchTimeMode)timeModeWithIdentifier:(id)fp8
{
	return kQCPatchTimeModeNone;
}

+ (Class)inspectorClassWithIdentifier:(id)fp8
{
	return [AudioEmbeddedFilePatchUI class];
}

-(void)dealloc
{
	[audioData release];
	[super dealloc];
}

// FIXME: possibly add canInstantiateWithFile: stuff back in someday...

- (id)initWithIdentifier:(id)fp8
{
	self=[super initWithIdentifier:fp8];
	if(self)
	{
		[inputCurrentVolume setDoubleValue:1.0];
		[inputCurrentVolume setMinDoubleValue:0.0];
		[inputCurrentVolume setMaxDoubleValue:1.0];
		
		[inputCurrentPosition setMinDoubleValue:0.0];
		[[self userInfo] setObject: @"Kineme Audio Embedded File Player" forKey: @"name"];
	}
	return self;
}

- (void)importData:(NSString*)filename
{
	[audioData release];
	audioData = [[NSData alloc] initWithContentsOfFile:filename];
}

- (BOOL)setup:(QCOpenGLContext *)context
{
	_allocatedSounds=[[NSMutableArray alloc] initWithCapacity:16];
	_executedSinceSetup=NO;
	
	return YES;
}
- (void)cleanup:(QCOpenGLContext *)context
{
	[_allocatedSounds release];
}

- (void)enable:(QCOpenGLContext *)context
{
	// if we've already executed, and the trigger was already on upon enable, launch playback (useful when switching between windowed-mode and fullscreen-mode)
	if( _executedSinceSetup && ![inputTrig wasUpdated] && [inputTrig booleanValue] )
		[self _startPlaying];
}

- (void)disable:(QCOpenGLContext *)context
{
	// stop any remaining sounds (since releasing the NSSound doesn't stop it)
	for(NSSound *s in _allocatedSounds)
	{
		// stop receiving events (we don't want to double-deallocate)
		[s setDelegate:nil];
		[s stop];
		//		NSLog(@"AudioFilePlayerPatch: %08x: release  (disable)",s);
	}
	
	// this automatically releases all of the child NSSound objects
	[_allocatedSounds removeAllObjects];
}

- (BOOL)execute:(QCOpenGLContext *)context time:(double)time arguments:(NSDictionary *)arguments
{
	// catch rising edge of trigger
	if( [inputTrig wasUpdated] && [inputTrig booleanValue] )
		[self _startPlaying];
	
	if( [inputLoop wasUpdated] && ![inputLoop booleanValue] )
		for(NSSound *s in _allocatedSounds)
			[s setLoops:NO];
	
	if( [inputCurrentVolume wasUpdated] )
	{
		const double volume = [inputCurrentVolume doubleValue];
		for(NSSound *s in _allocatedSounds)
			[s setVolume:volume];
	}
	
	if( [inputCurrentPosition wasUpdated] )
	{
		const double position = [inputCurrentPosition doubleValue];
		for(NSSound *s in _allocatedSounds)
			[s setCurrentTime:position];
	}
	
	_executedSinceSetup=YES;
	
	return YES;
}

- (void)_startPlayingThread:(NSSound*)s
{
	[s play];
	[s release];
}

- (void)_startPlaying
{
	// release happens in _startPlayingThread:
	NSSound *s = [[NSSound alloc] initWithData:audioData];
	
	if( !s )
		return;
	
	//	NSLog(@"AudioFilePlayerPatch: %08x: alloc",s);
	
	[s setLoops:[inputLoop booleanValue]];
	[s setVolume:[inputCurrentVolume doubleValue]];
	[s setCurrentTime:[inputCurrentPosition doubleValue]];
	
	// pick up the sound:didFinishPlaying message so we can dealloc the NSSound
	[s setDelegate:self];
	
	// if a playback device isn't specified, use the default (by not forcing the playback device)
	if( [[inputDeviceUID stringValue] length] )
	{
		@try
		{
			[s setPlaybackDeviceIdentifier:[inputDeviceUID stringValue]];
		}
		@catch(...)
		{
			[self logMessage:@"Failed to set output device UID '%@'.", [inputDeviceUID stringValue]];
			[s release];
			return;
		}
	}
	
	// if a channel mapping isn't specified, use the default (by not forcing the channel mapping)
	if( [[inputChannelMapping stringValue] length] )
	{
		NSMutableArray *channelMapping = [[NSMutableArray alloc] initWithCapacity:16];
		NSArray *channelMappingStrings = [[inputChannelMapping stringValue] componentsSeparatedByString:@","];
		for(NSString *s in channelMappingStrings)
			[channelMapping addObject:[NSNumber numberWithInteger:[s integerValue]]];
		[s setChannelMapping:channelMapping];
	}
	
	if([inputSynchronous booleanValue])
		[self _startPlayingThread: s];
	else
		[NSThread detachNewThreadSelector:@selector(_startPlayingThread:) toTarget:self withObject:s];
	
	
	[_allocatedSounds addObject:s];
}

- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)finishedPlaying
{
	[_allocatedSounds removeObject:sound];
}

- (NSDictionary*)state
{
	NSMutableDictionary *stateDict = [[[NSMutableDictionary alloc] init] autorelease];
	
	[stateDict addEntriesFromDictionary:[super state]];
	if(audioData)
		[stateDict setObject:audioData forKey:@"net.kineme.AudioTools.embeddedAudio"];			
	
	return stateDict;
}

- (BOOL)setState:(NSDictionary*)state
{
	audioData = [[state objectForKey:@"net.kineme.AudioTools.embeddedAudio"] retain];
	return [super setState:state];
}

@end
