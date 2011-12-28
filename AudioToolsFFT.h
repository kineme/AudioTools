#import <Accelerate/Accelerate.h>

@interface AudioToolsFFT : NSObject
{
	FFTSetup _fftSetup;
	DSPSplitComplex _split;
	float *_frequency;
	int _frameSize;
}

- (id)initWithFrameSize:(int)frameSize;
- (NSArray *)frequenciesForSampleData:(float *)sampleData numFrames:(int)numFrames usingChannel:(int)channel ofChannels:(int)numChannels frequencyMode:(int)frequencyMode;
@end
