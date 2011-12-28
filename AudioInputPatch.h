#import <CoreAudio/CoreAudio.h>
#import <pthread.h>

#import "AudioToolsFFT.h"

@interface AudioInputPatch : QCPatch
{
    QCStringPort *inputDeviceUID;
	QCIndexPort	 *inputFrequencyMode;

	QCStructurePort	*outputWaveform;
	QCStructurePort	*outputPeaks;
	QCStructurePort *outputFrequency;
	QCImagePort	*outputWaveformImage;

	QCStructure *audioData;
	QCStructure *audioPeaks;
	QCStructure *audioFreq;
	CGColorSpaceRef cs;
	QCPixelFormat *pf;
	NSString *deviceUID;
	AudioDeviceID device;
	AudioDeviceIOProcID procID;

	AudioToolsFFT *_fft;
	pthread_mutex_t dataLock;
}

- (id)initWithIdentifier:(id)fp8;

- (BOOL)setup:(QCOpenGLContext *)context;
- (void)cleanup:(QCOpenGLContext *)context;

- (void)enable:(QCOpenGLContext *)context;
- (void)disable:(QCOpenGLContext *)context;

- (void)setAudioData:(const AudioBufferList *)audioBufferList;

- (BOOL)execute:(QCOpenGLContext *)context time:(double)time arguments:(NSDictionary *)arguments;

- (void)connect;

- (void)setDeviceUID:(NSString*)uid;
- (NSString*)deviceUID;

@end