#import "AudioToolsFFT.h"

#import <AudioToolbox/AudioToolbox.h>

#ifndef __LP64__
#import <QuickTime/QuickTime.h>
#endif

@interface AudioFileInputPatch : QCPatch
{
	QCStringPort	*inputPath;
	QCIndexPort		*inputSampleBuffer;
	QCIndexPort		*inputFrequencyMode;

	QCStructurePort	*outputWaveform;
	QCStructurePort	*outputPeaks;
	QCStructurePort *outputFrequency;
	QCImagePort		*outputWaveformImage;
	
	ExtAudioFileRef audioFile;
	AudioBufferList	*mBufferList;
	float sampleRate;
	SInt64 headerFrames;
	CGColorSpaceRef cs;
	BOOL	isMP3;	// need to decode mp3s a bit differently to get meaningful datas...

#ifndef __LP64__
	Movie	movieFile;
	MovieAudioExtractionRef extractionSessionRef;
#endif
	
	AudioToolsFFT *_fft;
	int _requestedFrames;
}

- (id)initWithIdentifier:(id)fp8;

- (BOOL)setup:(QCOpenGLContext *)context;
- (void)cleanup:(QCOpenGLContext *)context;

- (void)enable:(QCOpenGLContext *)context;
- (void)disable:(QCOpenGLContext *)context;

- (BOOL)execute:(QCOpenGLContext *)context time:(double)time arguments:(NSDictionary *)arguments;
@end