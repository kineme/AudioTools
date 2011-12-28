#import "AudioInputPatch.h"

static OSStatus audioBufferHandler(AudioDeviceID		inDevice,
							   const AudioTimeStamp*	inNow,
							   const AudioBufferList*	inInputData,
							   const AudioTimeStamp*	inInputTime,
							   AudioBufferList*			outOutputData,
							   const AudioTimeStamp*	inOutputTime,
							   void*					inClientData)
{
	// we might've (accidentally) selected an audio device with no input channels
	if( inInputData->mNumberBuffers > 0 )
	{
//		NSLog(@"read stuff! (%i buffers)", inInputData->mNumberBuffers);

		AudioInputPatch *ai = (AudioInputPatch*)inClientData;
		NSAutoreleasePool *p = [[NSAutoreleasePool allocWithZone:NULL] init];
		[ai setAudioData:inInputData];
		[p drain];
	}

	return 0;
}

@implementation AudioInputPatch : QCPatch

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
	return kQCPatchTimeModeTimeBase;
}

- (void)setAudioData:(const AudioBufferList *)audioBufferList
{
	QCStructure *data = [[QCStructure allocWithZone:NULL] init], *chan, *fchan;
	QCStructure *peak = [[QCStructure allocWithZone:NULL] init];
	QCStructure *freq = [[QCStructure allocWithZone:NULL] init];
	unsigned int i, j;
	NSUInteger currentBuffer;
	NSUInteger currentChannel=0;
	unsigned int freqMode = [inputFrequencyMode indexValue];
	
	for(currentBuffer=0;currentBuffer<audioBufferList->mNumberBuffers;++currentBuffer)
	{
		AudioBuffer audioBuffer = audioBufferList->mBuffers[currentBuffer];
		
		float *sampleData = (float*)audioBuffer.mData;
		float max;
		unsigned int dataSize = audioBuffer.mDataByteSize/(audioBuffer.mNumberChannels * sizeof(float));
		
		for(j = 0; j < audioBuffer.mNumberChannels; ++j)
		{
			NSMutableArray *channel = [[NSMutableArray allocWithZone:NULL] initWithCapacity: dataSize];
			unsigned int offset = j;
			max  = 0;
			IMP addObject = [channel methodForSelector:@selector(addObject:)];
			for(i=0; i< dataSize; ++i)
			{
				CFNumberRef num = CFNumberCreate(NULL, kCFNumberFloatType, &sampleData[offset]);
				addObject(channel, @selector(addObject:), num);
				CFRelease(num);
				if( fabsf(sampleData[offset]) > max)
					max = fabsf(sampleData[offset]);
				offset += audioBuffer.mNumberChannels;
			}

			NSArray *freqChannel;
			if( freqMode )
			{
				freqChannel = [_fft
					frequenciesForSampleData:sampleData
					numFrames:dataSize
					usingChannel:j
					ofChannels:audioBuffer.mNumberChannels
					frequencyMode:freqMode
				];
			}
			else
				freqChannel = nil;

			chan = [[QCStructure allocWithZone:NULL] initWithArray: channel];
			fchan = [[QCStructure allocWithZone:NULL] initWithArray: freqChannel];
			[channel release];
			[freqChannel release];
			NSString *channelNumber = [[NSString allocWithZone:NULL] initWithFormat:@"channel%02i",currentChannel];
			[data addMember: chan forKey: channelNumber];
			[peak addMember: [NSNumber numberWithFloat: max] forKey: channelNumber];
			[freq addMember: fchan forKey: channelNumber];
			[channelNumber release];
			++currentChannel;
			[chan release];
			[fchan release];
		}
	}

	QCStructure *oldAudioFreq = audioFreq;
	QCStructure *oldAudioData = audioData;
	QCStructure *oldAudioPeaks = audioPeaks;
	pthread_mutex_lock(&dataLock);
	{
		audioFreq = freq;
		audioData = data;
		audioPeaks = peak;
	}
	pthread_mutex_unlock(&dataLock);
	[oldAudioFreq release];
	[oldAudioData release];
	[oldAudioPeaks release];	
}

- (id)initWithIdentifier:(id)fp8
{
	if(self=[super initWithIdentifier:fp8])
	{
		//[self connect];
		pf = [QCPixelFormat pixelFormatARGB8];
		[[self userInfo] setObject:@"Kineme Audio Input" forKey:@"name"];

		[inputFrequencyMode setIndexValue:0];
		[inputFrequencyMode setMaxIndexValue:3];
	}

	return self;
}

- (BOOL)setup:(QCOpenGLContext *)context
{
	pthread_mutex_init(&dataLock, NULL);
	_fft = [[AudioToolsFFT alloc] initWithFrameSize:512];

	[self setDeviceUID:[inputDeviceUID stringValue]];
	[self connect];
	
	return YES;
}
- (void)cleanup:(QCOpenGLContext *)context
{
	AudioDeviceDestroyIOProcID(device, procID);
	[_fft release];
	pthread_mutex_destroy(&dataLock);
}


- (void)enable:(QCOpenGLContext *)context
{
	cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
	AudioDeviceStart(device, procID);
}
- (void)disable:(QCOpenGLContext *)context
{
	AudioDeviceStop(device, procID);
	CGColorSpaceRelease(cs);
}

- (void)connect
{
	if(device)
	{
		AudioDeviceStop(device, procID);
		AudioDeviceDestroyIOProcID(device, procID);
	}
	
	UInt32 size, count;
	
	//device = kAudioHardwarePropertyDefaultInputDevice;//devices[0];
	size = sizeof(AudioDeviceID);
	if( (deviceUID == nil) || ([deviceUID length] == 0) )
	{
		//NSLog(@"using default input device");
		AudioHardwareGetProperty(kAudioHardwarePropertyDefaultInputDevice, &size, &device);
	}
	else
	{
		NSString *uid = nil;
		unsigned int i;
		AudioHardwareGetPropertyInfo(kAudioHardwarePropertyDevices, &size, NULL);
		//NSLog(@"%i devices", size / sizeof(AudioDeviceID));
		
		count = size/sizeof(AudioDeviceID);
		AudioDeviceID devices[count];
		AudioHardwareGetProperty(kAudioHardwarePropertyDevices,&size, &devices);
		for(i=0; i < count; ++i)
		{
			size = sizeof(NSString*);
			if(AudioDeviceGetProperty(devices[i],
									  0, YES,
									  kAudioDevicePropertyDeviceUID,
									  &size, &uid))
				NSLog(NSLocalizedString(@"Error getting device uid", @""));
			if([uid isEqual: deviceUID])
			{
				//NSLog(@"found matching device %i %@", devices[i],uid);
				device = devices[i];
			}
		}
	}
	
	//AudioDeviceAddIOProc(device, audioBufferHandler, self);
	//AudioDeviceStart(device, audioBufferHandler);
	if(AudioDeviceCreateIOProcID(device,
							  audioBufferHandler,
							  self,
							  &procID))
		NSLog(NSLocalizedString(@"Error creating IOProc", @""));
	//AudioDeviceStart(device, procID);
	
	AudioStreamBasicDescription recordFormat;
	
	size = sizeof(recordFormat);
	AudioHardwareGetProperty(kAudioDevicePropertyStreamFormat, &size, &recordFormat);
	if(recordFormat.mFormatFlags & kLinearPCMFormatFlagIsFloat == FALSE)
	{
		NSLog(NSLocalizedString(@"QCAudioInput:  non-floating samples not currently supported", @""));
	}
	//NSLog(@"float samples: %i",recordFormat.mFormatFlags & kLinearPCMFormatFlagIsFloat);
	//AudioDeviceStart(device, procID);
}

- (BOOL)execute:(QCOpenGLContext *)context time:(double)time arguments:(NSDictionary *)arguments
{
	if( [inputDeviceUID wasUpdated] )
		[self setDeviceUID:[inputDeviceUID stringValue]];

	if(audioData)
	{
		QCStructure *localAudioData;
		QCStructure *localAudioPeaks;
		QCStructure *localFreqData;

		pthread_mutex_lock(&dataLock);
		{
			localAudioData = [audioData retain];
			localAudioPeaks = [audioPeaks retain];
			localFreqData = [audioFreq retain];
		}
		pthread_mutex_unlock(&dataLock);
				
		/* This is usually true, but when it's not, we can skip everything.
		   if we're in non-vblsync mode, this is false most of the time (until our framerate drops to ~80-90 fps) */
		BOOL needsUpdate = ([outputWaveform structureValue] != localAudioData);
		if(needsUpdate)
		{
			[outputWaveform setStructureValue: localAudioData];
			[outputPeaks setStructureValue: localAudioPeaks];
			[outputFrequency setStructureValue: localFreqData];

			unsigned int i, j, count;
			
			unsigned int channelCount = [localAudioData count];
			count = [[localAudioData memberAtIndex:0] count];

			id audioDataMember;
			unsigned int value;
			QCImagePixelBuffer *pb;
			
			pb = [[context imageManager] createPixelBufferWithFormat: pf
														  pixelsWide: count
														  pixelsHigh: channelCount
															 options: nil];
			
			unsigned int rowBytes = [pb bytesPerRow]/sizeof(unsigned int);
			unsigned int *audioImageData = (unsigned int*)[pb baseAddress];

			[pb beginUpdatePixels:FALSE colorSpace: cs];
			for(j=0;j<channelCount;++j)
			{
				audioDataMember = [localAudioData memberAtIndex:j];
				i = 0;
				for(NSNumber *val in (NSArray*)[audioDataMember _list])
				{
					value = 127.f*(1.f+[val floatValue]);
					value *= 0x01010101;
					audioImageData[i] = value;
					++i;
				}
				audioImageData += rowBytes;
			}
			[pb endUpdatePixels];
			QCImage *audioImage = [[QCImage allocWithZone:NULL] initWithQCImageBuffer: pb options: nil];
			[outputWaveformImage setImageValue: audioImage];

			[pb release];
			[audioImage release];
		}
		[localAudioData release];
		[localFreqData release];
		[localAudioPeaks release];
	}
	else //  no data
	{
		[outputWaveform setStructureValue:nil];
		[outputPeaks setStructureValue:nil];
		[outputFrequency setStructureValue:nil];
		[outputWaveformImage setImageValue:nil];
	}
	
	return YES;
}

- (void)setDeviceUID:(NSString*)uid
{
	if([uid isEqual:deviceUID] == FALSE)
	{
		[deviceUID release];
		deviceUID = [uid retain];
		[self connect];	// stops the old device
		AudioDeviceStart(device, procID);
	}
}

-(NSString*)deviceUID
{
	return deviceUID;
}

@end
