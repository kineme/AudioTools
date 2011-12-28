#import "AudioDeviceInfoPatch.h"

#import <CoreAudio/CoreAudio.h>


@implementation AudioDeviceInfoPatch : QCPatch

+ (QCPatchExecutionMode)executionModeWithIdentifier:(id)fp8
{
	return kQCPatchExecutionModeProvider;
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
		[[self userInfo] setObject: @"Kineme Audio Device Info" forKey: @"name"];
	}
	
	return self;
}

- (void)enable:(QCOpenGLContext *)context
{
	NSMutableArray *inputDevices = [[NSMutableArray alloc] initWithCapacity:16];
	NSMutableArray *outputDevices = [[NSMutableArray alloc] initWithCapacity:16];


	UInt32 deviceCount;
	AudioDeviceID *audioDevices;
	{
		UInt32 sz;
		AudioHardwareGetPropertyInfo(kAudioHardwarePropertyDevices,&sz,NULL);
		audioDevices=(AudioDeviceID *)malloc(sz);
		AudioHardwareGetProperty(kAudioHardwarePropertyDevices,&sz,audioDevices);
		deviceCount = (sz / sizeof(AudioDeviceID));
	}
	
	UInt32 i;
	for(i=0;i<deviceCount;++i)
	{
		NSMutableDictionary *deviceInfoDictionary = [[NSMutableDictionary alloc] initWithCapacity:16];

		{
			UInt32 sz=sizeof(CFStringRef);
			NSString *s;
			AudioDeviceGetProperty(audioDevices[i],0,false,kAudioObjectPropertyName,&sz,&s);
			[deviceInfoDictionary setObject:s forKey:@"Name"];
			[s release];
		}

		{
			UInt32 sz=sizeof(CFStringRef);
			NSString *s;
			AudioDeviceGetProperty(audioDevices[i],0,false,kAudioObjectPropertyManufacturer,&sz,&s);
			[deviceInfoDictionary setObject:s forKey:@"Manufacturer"];
			[s release];
		}

		{
			UInt32 sz=sizeof(CFStringRef);
			NSString *s;
			AudioDeviceGetProperty(audioDevices[i],0,false,kAudioDevicePropertyDeviceUID,&sz,&s);
			[deviceInfoDictionary setObject:s forKey:@"UID"];
			[s release];
		}

		NSUInteger inputChannelCount = 0;
		{
			BOOL isInput=true;

			UInt32 sz=sizeof(CFStringRef);
			AudioDeviceGetPropertyInfo(audioDevices[i],0,isInput,kAudioDevicePropertyStreamConfiguration,&sz,NULL);
			AudioBufferList *bufferList=(AudioBufferList *)malloc(sz);
			AudioDeviceGetProperty(audioDevices[i],0,isInput,kAudioDevicePropertyStreamConfiguration,&sz,bufferList);

			UInt32 j;
			for(j=0;j<bufferList->mNumberBuffers;++j)
				inputChannelCount += bufferList->mBuffers[j].mNumberChannels;

			free(bufferList);

			[deviceInfoDictionary setObject:[NSNumber numberWithInt:inputChannelCount] forKey:@"InputChannels"];
		}
		
		NSUInteger outputChannelCount = 0;
		{
			BOOL isInput=false;

			UInt32 sz=sizeof(CFStringRef);
			AudioDeviceGetPropertyInfo(audioDevices[i],0,isInput,kAudioDevicePropertyStreamConfiguration,&sz,NULL);
			AudioBufferList *bufferList=(AudioBufferList *)malloc(sz);
			AudioDeviceGetProperty(audioDevices[i],0,isInput,kAudioDevicePropertyStreamConfiguration,&sz,bufferList);

			UInt32 j;
			for(j=0;j<bufferList->mNumberBuffers;++j)
				outputChannelCount += bufferList->mBuffers[j].mNumberChannels;

			free(bufferList);

			[deviceInfoDictionary setObject:[NSNumber numberWithInt:outputChannelCount] forKey:@"OutputChannels"];
		}

		if( inputChannelCount )
			[inputDevices addObject:deviceInfoDictionary];
		if( outputChannelCount )
			[outputDevices addObject:deviceInfoDictionary];

		[deviceInfoDictionary release];
	}


	{
		QCStructure *s = [[QCStructure alloc] initWithArray:inputDevices];
		[outputInputDevices setStructureValue:s];
		[s release];
	}

	{
		QCStructure *s = [[QCStructure alloc] initWithArray:outputDevices];
		[outputOutputDevices setStructureValue:s];
		[s release];
	}

	[inputDevices release];
	[outputDevices release];
}

@end
