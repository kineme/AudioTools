@interface AudioEmbeddedFilePlayerPatch : QCPatch
{
    QCStringPort *inputDeviceUID;
    QCStringPort *inputChannelMapping;
	QCBooleanPort *inputLoop;
	QCBooleanPort *inputTrig;
	
	QCNumberPort *inputCurrentVolume;
	QCNumberPort *inputCurrentPosition;
	
	QCBooleanPort *inputSynchronous;

	NSData *audioData;
	NSMutableArray *_allocatedSounds;
	BOOL _executedSinceSetup;
}

- (id)initWithIdentifier:(id)fp8;

- (void)cleanup:(QCOpenGLContext *)context;
- (void)enable:(QCOpenGLContext *)context;
- (void)disable:(QCOpenGLContext *)context;

- (BOOL)execute:(QCOpenGLContext *)context time:(double)time arguments:(NSDictionary *)arguments;

- (void)importData:(NSString*)filename;

- (void)_startPlayingThread:(NSSound*)s;
- (void)_startPlaying;
@end