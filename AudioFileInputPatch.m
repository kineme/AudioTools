#import "AudioFileInputPatch.h"

#ifndef __LP64__
//////////
//
// GetMovieFromCFURLRef
// Instantiate a QuickTime movie for a QuickTime movie file CFURL.
// 
//////////

static OSErr GetMovieFromCFURLRef(CFURLRef inURLRef, Movie *outMovieRef)
{
	Handle outDataRef;
	OSType outDataRefType;
	
	// first create a QuickTime data reference for our CFURL
	OSErr err = QTNewDataReferenceFromCFURL(inURLRef,
                                            0,
                                            &outDataRef,
                                            &outDataRefType);
	if(err != noErr)
		return err;
	
	DataReferenceRecord dataRefRecord;
	Boolean		active = true;
	
	dataRefRecord.dataRefType = outDataRefType;
	dataRefRecord.dataRef = outDataRef;
	
    QTNewMoviePropertyElement newMovieProperties[] = 
    {  
        {kQTPropertyClass_DataLocation, kQTDataLocationPropertyID_DataReference, sizeof(dataRefRecord), &dataRefRecord, 0},
		{kQTPropertyClass_NewMovieProperty, kQTNewMoviePropertyID_Active, sizeof(active), &active, 0},
	};
	
	// instantiate a QuickTime movie from our CFURL data reference
    err = NewMovieFromProperties(sizeof(newMovieProperties) / sizeof(newMovieProperties[0]), newMovieProperties, 0, nil, outMovieRef);
    DisposeHandle(outDataRef);
	
	return err;
}
#endif

@implementation AudioFileInputPatch : QCPatch

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

- (id)initWithIdentifier:(id)fp8
{
	if(self=[super initWithIdentifier:fp8])
	{
		[[self userInfo] setObject: @"Kineme Audio File Input" forKey: @"name"];

		[inputSampleBuffer setIndexValue:1]; // 512
		_requestedFrames = 512;
		[inputSampleBuffer setMaxIndexValue:8];

		[inputFrequencyMode setIndexValue:0];
		[inputFrequencyMode setMaxIndexValue:3];
	}
	
	return self;
}

- (BOOL)setup:(QCOpenGLContext *)context
{
	_fft = [[AudioToolsFFT alloc] initWithFrameSize:_requestedFrames];
	
	return YES;
}

- (void)cleanup:(QCOpenGLContext *)context
{
	if(audioFile)
	{
		ExtAudioFileDispose(audioFile);
		audioFile = NULL;
	}
#ifndef __LP64__
	if(movieFile)
	{
		MovieAudioExtractionEnd(extractionSessionRef);
		DisposeMovie(movieFile);
		movieFile = NULL;
	}
#endif
	
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

	if( [inputPath wasUpdated] || requestedFramesUpdated )
	{
		NSString *path = KIExpandPath(self, [inputPath stringValue]);
		NSURL *url = [NSURL fileURLWithPath: path];
				
		if(audioFile)
		{
			ExtAudioFileDispose(audioFile);
			audioFile = NULL;
			if(mBufferList && mBufferList->mBuffers[0].mData)
				free(mBufferList->mBuffers[0].mData);
			if(mBufferList)
				free(mBufferList);
			mBufferList = NULL;
		}
#ifndef __LP64__
		if(movieFile)
		{
			MovieAudioExtractionEnd(extractionSessionRef);
			DisposeMovie(movieFile);
			movieFile = NULL;
			if(mBufferList && mBufferList->mBuffers[0].mData)
				free(mBufferList->mBuffers[0].mData);
			if(mBufferList)
				free(mBufferList);
			mBufferList = NULL;
		}
#endif		
		CFStringRef itemUTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)[path pathExtension], NULL);
		if(UTTypeConformsTo(itemUTI, kUTTypeAudio))
		{
			if(ExtAudioFileOpenURL((CFURLRef)url, &audioFile))
			{
				[self logMessage:@"Error opening '%@'", [inputPath stringValue]];
				audioFile = NULL;
				return YES;
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
				audioFile = NULL;
				return YES;
			}
			
			/*NSLog(@"asbd infos: (size = %i vs. %i)", size, sizeof(fileAsbd));
			
			NSLog(@"   * Sample Rate:   %8f", fileAsbd.mSampleRate);
			NSLog(@"   * FormatID:      %i", fileAsbd.mFormatID);
			NSLog(@"   * FormatFlags:   %x", fileAsbd.mFormatFlags);
			NSLog(@"   * b per packet:  %i", fileAsbd.mBytesPerPacket);
			NSLog(@"   * f per packet:  %i", fileAsbd.mFramesPerPacket);
			NSLog(@"   * b per frame:   %i", fileAsbd.mBytesPerFrame);
			NSLog(@"   * channels:      %i", fileAsbd.mChannelsPerFrame);
			NSLog(@"   * bit depth:     %i", fileAsbd.mBitsPerChannel);*/
			mBufferList->mBuffers[0].mNumberChannels = 2;
			mBufferList->mBuffers[0].mDataByteSize = requestedFrames*4*fileAsbd.mChannelsPerFrame;
			mBufferList->mBuffers[0].mData = malloc(requestedFrames*4*fileAsbd.mChannelsPerFrame);
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
			
			if(ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(clientAsbd), &clientAsbd))
			{
				[self logMessage: @"Error setting client properties!"];
				ExtAudioFileDispose(audioFile);
				audioFile = NULL;
				return YES;
			}
			AudioConverterRef acRef;
			UInt32 acrsize=sizeof(AudioConverterRef);
			if(ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_AudioConverter, &acrsize, &acRef))
			{
				[self logMessage: @"Error getting audio converter!"];
				ExtAudioFileDispose(audioFile);
				audioFile = NULL;
				return YES;
			}
			
			AudioConverterPrimeInfo primeInfo;
			UInt32 piSize=sizeof(AudioConverterPrimeInfo);
			if(AudioConverterGetProperty(acRef, kAudioConverterPrimeInfo, &piSize, &primeInfo) != kAudioConverterErr_PropertyNotSupported)
				headerFrames = primeInfo.leadingFrames;
			else
				headerFrames = 0;
		}
		else if(UTTypeConformsTo(itemUTI, kUTTypeMovie))
		{
#ifndef __LP64__
			if(GetMovieFromCFURLRef((CFURLRef)url, &movieFile) == noErr)
				MovieAudioExtractionBegin(movieFile, 0, &extractionSessionRef);
			else
			{
				[self logMessage:@"Error opening '%@'", [inputPath stringValue]];
				movieFile = NULL;
				return YES;
			}
			
			// See http://lists.apple.com/archives/Coreaudio-api/2006/Nov/msg00116.html for 64-bit insanity on this
			mBufferList = (AudioBufferList*)calloc(1,sizeof(AudioBufferList));
			
			OSStatus err;
			
			Boolean allChannelsDiscrete = true;
			
			// disable mixing of audio channels
			err = MovieAudioExtractionSetProperty(extractionSessionRef,
												  kQTPropertyClass_MovieAudioExtraction_Movie,
												  kQTMovieAudioExtractionMoviePropertyID_AllChannelsDiscrete,
												  sizeof (Boolean), &allChannelsDiscrete);
			AudioStreamBasicDescription asbd;
			
			// Get the default audio extraction ASBD
			err = MovieAudioExtractionGetProperty(extractionSessionRef,
												  kQTPropertyClass_MovieAudioExtraction_Audio,
												  kQTMovieAudioExtractionAudioPropertyID_AudioStreamBasicDescription,
												  sizeof (asbd), &asbd, nil);
			
			//NSLog(@"asbd infos: (size = %i vs. %i)",, sizeof(asbd));
			 
			/*NSLog(@"   * Sample Rate:   %8f", asbd.mSampleRate);
			NSLog(@"   * FormatID:      %i", asbd.mFormatID);
			NSLog(@"   * FormatFlags:   %x", asbd.mFormatFlags);
			NSLog(@"   * b per packet:  %i", asbd.mBytesPerPacket);
			NSLog(@"   * f per packet:  %i", asbd.mFramesPerPacket);
			NSLog(@"   * b per frame:   %i", asbd.mBytesPerFrame);
			NSLog(@"   * channels:      %i", asbd.mChannelsPerFrame);
			NSLog(@"   * bit depth:     %i", asbd.mBitsPerChannel);*/
			
			mBufferList->mBuffers[0].mNumberChannels = 2;
			mBufferList->mBuffers[0].mDataByteSize = requestedFrames*4*asbd.mChannelsPerFrame;
			mBufferList->mBuffers[0].mData = malloc(requestedFrames*4*asbd.mChannelsPerFrame);
			mBufferList->mBuffers[0].mNumberChannels = asbd.mChannelsPerFrame;			

#if defined (__ppc__) || (__ppc64__)
			asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian;
#elif (__i386__) || (__x86_64__)
			asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
#else
#error what arch is this?
#endif
			asbd.mBitsPerChannel = sizeof(float) * 8;
			asbd.mBytesPerFrame = sizeof(float) * asbd.mChannelsPerFrame;
			asbd.mBytesPerPacket = asbd.mBytesPerFrame;
			
			// Set the new audio extraction ASBD (ensure float samples)
			err = MovieAudioExtractionSetProperty(extractionSessionRef,
												  kQTPropertyClass_MovieAudioExtraction_Audio,
												  kQTMovieAudioExtractionAudioPropertyID_AudioStreamBasicDescription,
												  sizeof (asbd), &asbd);
			//NSLog(@"set err: %i", err);
#endif
		}
		CFRelease(itemUTI);
	}

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
#ifndef __LP64__
	else if(movieFile)
	{
		OSStatus err;
		TimeRecord timeRec;
		
		timeRec.scale	= GetMovieTimeScale(movieFile);
		timeRec.base	= NULL;
		timeRec.value.hi = 0;
		timeRec.value.lo = time * timeRec.scale;
		
		// Set the extraction current time.  The duration will 
		// be determined by how much is pulled.
		err = MovieAudioExtractionSetProperty(extractionSessionRef,
											  kQTPropertyClass_MovieAudioExtraction_Movie,
											  kQTMovieAudioExtractionMoviePropertyID_CurrentTime,
											  sizeof(TimeRecord), &timeRec);
		if(err!= noErr)
			NSLog(@"error setting time: %i", err);

		UInt32 flags = 0;
		UInt32 numFrames = requestedFrames;
		mBufferList->mNumberBuffers = 1;
		mBufferList->mBuffers[0].mDataByteSize = requestedFrames*4 * mBufferList->mBuffers[0].mNumberChannels;
		// clear so if we go over we get proper zeros at the end if we have a partial packet
		bzero(mBufferList->mBuffers[0].mData, mBufferList->mBuffers[0].mNumberChannels * requestedFrames * sizeof(float));
		
		err = MovieAudioExtractionFillBuffer(extractionSessionRef, &numFrames, mBufferList, &flags);
		if (flags & kQTMovieAudioExtractionComplete)
		{
			// extraction complete!
			//NSLog(@"extraction complete!");
		}
		//NSLog(@"numFrames: %i flags: %x err: %i", numFrames, flags, err);
	}
#endif
	{
		if(mBufferList && mBufferList->mBuffers[0].mNumberChannels)
		{
			QCStructure *data = [[QCStructure allocWithZone:NULL] init], *chan, *fchan;
			QCStructure *peak = [[QCStructure allocWithZone:NULL] init];
			QCStructure *freq = [[QCStructure allocWithZone:NULL] init];
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
						CFNumberRef num = CFNumberCreate(NULL, kCFNumberFloatType, &sampleData[offset]);
						addObject(channel,@selector(addObject:),num);
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
					{
						freqChannel = nil;
					}
					
					chan = [[QCStructure allocWithZone:NULL] initWithArray: channel];
					fchan = [[QCStructure allocWithZone:NULL] initWithArray: freqChannel];
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
			QCImage *audioImage = [[QCImage allocWithZone:NULL] initWithQCImageBuffer: pb options: nil];
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

@end
