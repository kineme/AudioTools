#import "AudioToolsFFT.h"

@implementation AudioToolsFFT

- (id)initWithFrameSize:(int)frameSize
{
	if(self=[super init])
	{
//		NSLog(@"AudioToolsFFT::initWithFrameSize:%d",frameSize);
		_fftSetup = vDSP_create_fftsetup( log2f(frameSize), kFFTRadix2 );
		// WARNING:  we're minimizing allocations here, but we _have_ to keep in mind that _split.realp and _split.imagp _MUST_ by
		// 16-byte aligned.  malloc/calloc will automatically do this for us, but pointer math will NOT.
		// float is 4 bytes, so frameSize _MUST_ be a multiple of 4 to ensure that we're always 16-byte aligned later on.
		// This is currently guaranteed, with frameSize being between 256 and 65536.
		_frequency = (float*)calloc(sizeof(float)*frameSize * 2, 1);
		_split.realp = _frequency + frameSize;
		_split.imagp = _split.realp + frameSize / 2;
		_frameSize = frameSize;
	}
    return self;
}


- (void)dealloc
{
	vDSP_destroy_fftsetup(_fftSetup);
	free(_frequency);

	[super dealloc];
}


// @@@ needs proper windowing http://stackoverflow.com/a/1959900/64860
- (NSArray *)frequenciesForSampleData:(float *)sampleData numFrames:(int)numFrames usingChannel:(int)channel ofChannels:(int)numChannels frequencyMode:(int)frequencyMode
{
//	NSLog(@"[AudioToolsFFT frequenciesForSampleData] frames=%d",numFrames);

	// maybe use CFMutableArray to avoid the IMP caching ugliness -- need to profile
	NSMutableArray *freqChannel = [(NSMutableArray*)[NSMutableArray allocWithZone:NULL] initWithCapacity: numFrames];
	// see vDSP_Library.pdf, page 20

	// turn channel of (real) sampleData into a (real) even-odd array (despite the DSPSplitComplex datatype).
	unsigned int offset = channel;
	unsigned int i;
	DSPSplitComplex lSplit = _split;

	for( i=0; i<numFrames/(2*numChannels); ++i )
	{
		lSplit.realp[i] = sampleData[offset];
		offset += numChannels;
		lSplit.imagp[i] = sampleData[offset];
		offset += numChannels;
	}
	
	// perform real-to-complex FFT.
	vDSP_fft_zrip( _fftSetup, &lSplit, 1, log2f(_frameSize), kFFTDirection_Forward );
	
	// scale by 1/2*n because vDSP_fft_zrip doesn't use the right scaling factors natively ("for better performances")
	{
		const float scale = 1.0f/(2.0f*(float)numFrames);
		vDSP_vsmul( lSplit.realp, 1, &scale, lSplit.realp, 1, numFrames/2 );
		vDSP_vsmul( lSplit.imagp, 1, &scale, lSplit.imagp, 1, numFrames/2 );				
	}
	
	// collapse split complex array into a real array.
	// split[0] contains the DC, and the values we're interested in are split[1] to split[len/2] (since the rest are complex conjugates)
	vDSP_zvabs( &lSplit, 1, _frequency, 1, numFrames/2 );

	// @@@ on some composition launches (about 1 out of 100 or so?), vDSP_fft_zrip mysteriously returns an array full of NANs.
	// perhaps someday we can figure out what triggers this.
	//if(!isfinite(_frequency[0]))
	//	NSLog(@"[AudioToolsFFT frequenciesForSampleData]  vDSP_fft_zrip() mysteriously returned NAN, not sure why.  This is going to break the Frequency output.");
	
	float *lFrequency = _frequency;
	
	id num;
	switch(frequencyMode)
	{
		case 1:	// Linear Raw
		{
			IMP addObject = [freqChannel methodForSelector:@selector(addObject:)];
			for( i=1; i<numFrames/2; ++i )
			{
				float val = lFrequency[i] * ((float)sqrtf(i)*2.f + 1.f);
				CFNumberRef num = CFNumberCreate(NULL, kCFNumberFloatType, &val);
				addObject(freqChannel, @selector(addObject:), num);
				CFRelease(num);
			}
			break;
		}
		case 2:	// Quadratic Average
		{
			int lowerFrequency = 1, upperFrequency;
			int k;
			float sum;
			bool done=NO;
			i=0;
			while(!done)
			{
				upperFrequency = lowerFrequency + i;
				sum=0.f;
				if( upperFrequency >= numFrames/2 )
				{
					upperFrequency = numFrames/2-1;
					done=YES;
				}
				for( k=lowerFrequency; k<=upperFrequency; ++k )
					sum += lFrequency[k];
				sum /= (float)(upperFrequency-lowerFrequency+1);
				sum *= (float)i*2.f + 1.f;
				num = [[NSNumber allocWithZone:NULL] initWithFloat:sum];
				[freqChannel addObject: num ];
				[num release];
				lowerFrequency = upperFrequency;
				++i;
			}
			break;
		}
		case 3:	// Logarithmic Average
		{
			const float log2FrameSize = log2f(_frameSize);
			int numBuckets = log2FrameSize;
			int lowerFrequency, upperFrequency;
			int k;
			float sum;
			for( i=0; i<numBuckets; ++i)
			{
				lowerFrequency = (numFrames/2) / powf(2.f,log2FrameSize-i  )+1;
				upperFrequency = (numFrames/2) / powf(2.f,log2FrameSize-i-1)+1;
				sum=0.f;
				if(upperFrequency>=numFrames/2)
					upperFrequency=numFrames/2-1;
				for( k=lowerFrequency; k<=upperFrequency; ++k )
					sum += lFrequency[k];
				sum /= (float)(upperFrequency-lowerFrequency+1);
				sum *= (float)powf(i,1.5f) + 1.f;
				num = [[NSNumber allocWithZone:NULL] initWithFloat:sum];
				[freqChannel addObject: num ];
				[num release];
			}
		}
	}

	return freqChannel;
}

@end
