#import "AudioEmbeddedFileInputPatch.h"
#import "AudioEmbeddedFilePatchUI.h"

#pragma mark embedded audio callbacks

static OSStatus dataBufferReadProc(void * inClientData,
								   SInt64 inPosition, 
								   UInt32 requestCount, 
								   void * buffer, 
								   UInt32 *actualCount)
{
	//NSLog(@"readProc %i from %i", requestCount, inPosition);
	*actualCount = [(AudioEmbeddedFileInputPatch*)inClientData readToBuffer:buffer fromPosition:inPosition count:requestCount];
	//NSLog(@"actualCount: %i", *actualCount);
	return noErr;
}

static OSStatus dataBufferWriteProc(void * 		inClientData,
									SInt64		inPosition, 
									UInt32		requestCount, 
									const void *buffer, 
									UInt32    * actualCount)
{
	NSLog(NSLocalizedString(@"writeProc", @""));
	return kAudioFileOperationNotSupportedError; // Not Possible ;)
}

static SInt64 dataBufferGetSizeProc(void *inClientData)
{
	return [(AudioEmbeddedFileInputPatch*)inClientData dataSize];
}

static OSStatus dataBufferSetSizeProc(void * inClientData, SInt64 inSize)
{
	NSLog(NSLocalizedString(@"setSizeProc", @""));
	return kAudioFileOperationNotSupportedError; // Not Possible ;)
}


@implementation AudioEmbeddedFileInputPatch : QCPatch

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

+ (Class)inspectorClassWithIdentifier:(id)fp8
{
	return [AudioEmbeddedFilePatchUI class];
}

- (id)initWithIdentifier:(id)fp8
{
	if(self=[super initWithIdentifier:fp8])
	{
		[[self userInfo] setObject: @"Kineme Embedded Audio File Input" forKey: @"name"];
		
		[inputSampleBuffer setIndexValue:1]; // 512
		_requestedFrames = 512;
		[inputSampleBuffer setMaxIndexValue:8];
		
		[inputFrequencyMode setIndexValue:0];
		[inputFrequencyMode setMaxIndexValue:3];
	}
	
	return self;
}

- (void)importData:(NSString*)filename
{
	[audioData release];
	audioData = [[NSData alloc] initWithContentsOfFile:filename];
	[self _openData];
}

- (void)dealloc
{
	[audioData release];
	[super dealloc];
}

- (BOOL)setup:(QCOpenGLContext *)context
{
	_fft = [[AudioToolsFFT alloc] initWithFrameSize:_requestedFrames];
	[self _openData];
	
	return YES;
}

- (void)cleanup:(QCOpenGLContext *)context
{
	if(audioFile)
	{
		ExtAudioFileDispose(audioFile);
		AudioFileClose(audioDataFile);
		audioFile = NULL;
		audioDataFile = NULL;
	}
	
	if(mBufferList && mBufferList->mBuffers[0].mData)
		free(mBufferList->mBuffers[0].mData);
	if(mBufferList)
		free(mBufferList);
	mBufferList = NULL;
	
	[_fft release];
}

- (void)enable:(QCOpenGLContext *)context
{
	cs = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB); 
}
- (void)disable:(QCOpenGLContext *)context
{
	CGColorSpaceRelease(cs);
}

- (void)_openData
{
	if(audioFile)
	{
		ExtAudioFileDispose(audioFile);
		audioFile = NULL;
		AudioFileClose(audioDataFile);
		audioDataFile = NULL;
		
		if(mBufferList && mBufferList->mBuffers[0].mData)
			free(mBufferList->mBuffers[0].mData);
		if(mBufferList)
			free(mBufferList);
		mBufferList = NULL;
	}
	
	{
		OSStatus err;
		if((err = AudioFileOpenWithCallbacks(self,
											 dataBufferReadProc,
											 dataBufferWriteProc,
											 dataBufferGetSizeProc,
											 dataBufferSetSizeProc,
											 0,	// hint -- M4A hint doesn't seem to work though :/
											 &audioDataFile)) != noErr)
		{
			NSLog(NSLocalizedString(@"failed to open data with callbacks: %08x", @""), err);
			audioDataFile = NULL;
			return;
		}
		if(ExtAudioFileWrapAudioFileID(audioDataFile, NO, &audioFile) != noErr)
		{
			NSLog(NSLocalizedString(@"failed to wrap audioFile", @""));
			AudioFileClose(audioDataFile);
			audioFile = NULL;
			audioDataFile = NULL;
			return;
		}
		
		// See http://lists.apple.com/archives/Coreaudio-api/2006/Nov/msg00116.html for 64-bit insanity on this
		mBufferList = (AudioBufferList*)calloc(1,sizeof(AudioBufferList));
		
		AudioStreamBasicDescription fileAsbd, clientAsbd;
		UInt32 size = sizeof(fileAsbd);
		bzero(&fileAsbd,size);
		bzero(&clientAsbd, size);
		if(ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileDataFormat, &size, &fileAsbd))
		{
			[self logMessage: @"Error reading audio file properties!"];
			ExtAudioFileDispose(audioFile);
			AudioFileClose(audioDataFile);
			audioDataFile = NULL;
			audioFile = NULL;
			return;
		}
		
		mBufferList->mBuffers[0].mNumberChannels = 2;
		mBufferList->mBuffers[0].mDataByteSize = _requestedFrames*4*fileAsbd.mChannelsPerFrame;
		mBufferList->mBuffers[0].mData = malloc(_requestedFrames*4*fileAsbd.mChannelsPerFrame);
		mBufferList->mBuffers[0].mNumberChannels = fileAsbd.mChannelsPerFrame;
		
		sampleRate = fileAsbd.mSampleRate;
		clientAsbd.mSampleRate = fileAsbd.mSampleRate;
#if defined (__ppc__) || (__ppc64__)
		clientAsbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian;
#elif (__i386__) || (__x86_64__)
		clientAsbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
#else
#error what arch is this?
#endif
		clientAsbd.mFormatID = kAudioFormatLinearPCM;
		clientAsbd.mChannelsPerFrame = fileAsbd.mChannelsPerFrame;
		clientAsbd.mFramesPerPacket = 1;
		clientAsbd.mBytesPerFrame = sizeof(float) * fileAsbd.mChannelsPerFrame;
		clientAsbd.mBytesPerPacket = clientAsbd.mBytesPerFrame;
		clientAsbd.mBitsPerChannel = sizeof(float) * 8;
		if(fileAsbd.mFormatID == kAudioFormatMPEGLayer3)
			isMP3 = YES;
		else
			isMP3 = NO;
		
		SInt64 length;
		size = sizeof(length);
		if(ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileLengthFrames, &size, &length))
		{
			[self logMessage: @"Error getting audio length"];
			ExtAudioFileDispose(audioFile);
			AudioFileClose(audioDataFile);
			audioDataFile = NULL;
			audioFile = NULL;
			return;
		}
		[outputDuration setDoubleValue:length/sampleRate];
		
		if(ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(clientAsbd), &clientAsbd))
		{
			[self logMessage: @"Error setting client properties!"];
			ExtAudioFileDispose(audioFile);
			AudioFileClose(audioDataFile);
			audioDataFile = NULL;
			
			audioFile = NULL;
			return;
		}
		AudioConverterRef acRef;
		UInt32 acrsize=sizeof(AudioConverterRef);
		if(ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_AudioConverter, &acrsize, &acRef))
		{
			[self logMessage: @"Error getting audio converter!"];
			ExtAudioFileDispose(audioFile);
			AudioFileClose(audioDataFile);
			audioDataFile = NULL;
			
			audioFile = NULL;
			return;
		}
		
		AudioConverterPrimeInfo primeInfo;
		UInt32 piSize=sizeof(AudioConverterPrimeInfo);
		if(AudioConverterGetProperty(acRef, kAudioConverterPrimeInfo, &piSize, &primeInfo) != kAudioConverterErr_PropertyNotSupported)
			headerFrames = primeInfo.leadingFrames;
		else
			headerFrames = 0;
	}
}

- (BOOL)execute:(QCOpenGLContext *)context time:(double)time arguments:(NSDictionary *)arguments
{
	int requestedFrames = 0x100 << [inputSampleBuffer indexValue];
	bool requestedFramesUpdated = NO;
	if( requestedFrames != _requestedFrames)
	{
		[_fft release];
		_fft = [[AudioToolsFFT alloc] initWithFrameSize:requestedFrames];
		_requestedFrames = requestedFrames;
		requestedFramesUpdated = YES;
	}
	
	if(requestedFramesUpdated )
		[self _openData];

	
	if(audioFile)
	{
		UInt32 numFrames = requestedFrames;
		mBufferList->mNumberBuffers = 1;
		mBufferList->mBuffers[0].mDataByteSize = requestedFrames*4 * mBufferList->mBuffers[0].mNumberChannels;
		// clear so if we go over we get proper zeros at the end if we have a partial packet
		bzero(mBufferList->mBuffers[0].mData,mBufferList->mBuffers[0].mNumberChannels * requestedFrames * sizeof(float));
		
		
		if(isMP3)
		{
			// MP3 is dumb, and produces silence for the first few hundred samples after a seek.
			// to work around that, we seek to 1024 samples before our desired point, and decode twice to catch up
			// with a populated decoder stream.
			if(ExtAudioFileSeek(audioFile, MAX(time * sampleRate + headerFrames - 1024, headerFrames)) )
			{
				[self logMessage: @"Error seeking to current frame...!"];
				return YES;
			}
			ExtAudioFileRead(audioFile, &numFrames, mBufferList);
			numFrames = 512;
			ExtAudioFileRead(audioFile, &numFrames, mBufferList);
			numFrames = 512;
		}
		else
		{
			if(ExtAudioFileSeek(audioFile, time * sampleRate + headerFrames))
			{
				[self logMessage: @"Error seeking to current frame...!"];
				return YES;
			}
		}
		
		if(ExtAudioFileRead(audioFile, &numFrames, mBufferList) || numFrames != requestedFrames)
		{
			// if we can't read all samples (EOF or error), manually set our buffer size stuff
			mBufferList->mBuffers[0].mDataByteSize = mBufferList->mBuffers[0].mNumberChannels * requestedFrames * sizeof(float);
		}
	}

	{
		if(mBufferList && mBufferList->mBuffers[0].mNumberChannels)
		{
			QCStructure *data = [[QCStructure alloc] init], *chan, *fchan;
			QCStructure *peak = [[QCStructure alloc] init];
			QCStructure *freq = [[QCStructure alloc] init];
			unsigned int i, j;
			NSUInteger currentChannel=0;
			
			{
				AudioBuffer audioBuffer = mBufferList->mBuffers[0];
				
				float *sampleData = (float*)audioBuffer.mData;
				float max;
				unsigned int dataSize = audioBuffer.mDataByteSize/(audioBuffer.mNumberChannels * sizeof(float));
				
				unsigned int freqMode = [inputFrequencyMode indexValue];
				
				for(j = 0; j < audioBuffer.mNumberChannels; ++j)
				{
					NSMutableArray *channel = [[NSMutableArray alloc] initWithCapacity: dataSize];
					IMP addObject = [channel methodForSelector:@selector(addObject:)];
					unsigned int offset = j;
					max = 0;
					for(i=0; i< dataSize; ++i)
					{
						addObject(channel,@selector(addObject:),[NSNumber numberWithFloat: sampleData[offset]]);;
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
					{
						freqChannel = nil;
					}
					
					chan = [[QCStructure alloc] initWithArray: channel];
					fchan = [[QCStructure alloc] initWithArray: freqChannel];
					[channel release];
					[freqChannel release];
					NSString *channelNumber = [NSString stringWithFormat:@"channel%02i",currentChannel];
					[data addMember: chan forKey: channelNumber];
					[peak addMember: [NSNumber numberWithFloat: max] forKey: channelNumber];
					[freq addMember: fchan forKey: channelNumber];
					++currentChannel;
					[chan release];
					[fchan release];
				}
			}
			[outputWaveform setStructureValue: data];
			[outputPeaks setStructureValue: peak];
			[outputFrequency setStructureValue: freq];
			[data release];
			[peak release];
			[freq release];
			
			QCImagePixelBuffer *pb = [[context imageManager] createPixelBufferWithFormat: [QCPixelFormat pixelFormatARGB8]
																			  pixelsWide: requestedFrames
																			  pixelsHigh: mBufferList->mBuffers[0].mNumberChannels
																				 options: nil];
			
			unsigned int *audioImageData = (unsigned int*)[pb baseAddress];
			unsigned int rowBytes = [pb bytesPerRow]/sizeof(unsigned int);
			
			[pb beginUpdatePixels: FALSE colorSpace: cs];
			float *floatData = (float*)mBufferList->mBuffers[0].mData;
			unsigned int stride = mBufferList->mBuffers[0].mNumberChannels;
			for(j=0;j<mBufferList->mBuffers[0].mNumberChannels;++j)
			{
				unsigned int offset = j;
				for(i=0;i<requestedFrames;++i)
				{
					unsigned int value = (127.f * (1.0f + floatData[offset]));
					value *= 0x01010101;
					audioImageData[i] = value;
					offset += stride;
				}
				audioImageData += rowBytes;
			}
			[pb endUpdatePixels];
			QCImage *audioImage = [[QCImage alloc] initWithQCImageBuffer: pb options: nil];
			[outputWaveformImage setImageValue: audioImage];
			[audioImage release];
			[pb release];
		}
		else // no buffers = no/invalid input file
		{
			[outputWaveformImage setImageValue:nil];
			[outputWaveform setStructureValue:nil];
			[outputPeaks setStructureValue:nil];
			[outputFrequency setStructureValue:nil];
		}
	}
	
	return YES;
}

- (SInt64)dataSize
{
	return [audioData length];
}

- (UInt32)readToBuffer:(void*)buffer fromPosition:(SInt64)inPosition count:(UInt32)count
{
	NSRange r = NSMakeRange(inPosition, count);
	[audioData getBytes:buffer range:r];
	return count;
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
