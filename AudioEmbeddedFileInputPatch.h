#import "AudioToolsFFT.h"

#import <AudioToolbox/AudioToolbox.h>

@interface AudioEmbeddedFileInputPatch : QCPatch
{
	QCIndexPort		*inputSampleBuffer;
	QCIndexPort		*inputFrequencyMode;
	
	QCStructurePort	*outputWaveform;
	QCStructurePort	*outputPeaks;
	QCStructurePort *outputFrequency;
	QCImagePort		*outputWaveformImage;
	
	QCNumberPort	*outputDuration;
	
	NSData *audioData;
	
	AudioFileID audioDataFile;
	ExtAudioFileRef audioFile;
	AudioBufferList	*mBufferList;
	float sampleRate;
	SInt64 headerFrames;
	CGColorSpaceRef cs;
	BOOL	isMP3;	// need to decode mp3s a bit differently to get meaningful datas...
		
	AudioToolsFFT *_fft;
	int _requestedFrames;
}

- (id)initWithIdentifier:(id)fp8;

- (BOOL)setup:(QCOpenGLContext *)context;
- (void)cleanup:(QCOpenGLContext *)context;

- (void)enable:(QCOpenGLContext *)context;
- (void)disable:(QCOpenGLContext *)context;

- (void)_openData;

- (BOOL)execute:(QCOpenGLContext *)context time:(double)time arguments:(NSDictionary *)arguments;

- (SInt64)dataSize;
- (UInt32)readToBuffer:(void*)buffer fromPosition:(SInt64)inPosition count:(UInt32)count;
@end