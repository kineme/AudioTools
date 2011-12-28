@interface AudioFilePlayerPatch : QCPatch
{
    QCStringPort *inputPath;

    QCStringPort *inputDeviceUID;
    QCStringPort *inputChannelMapping;
	QCBooleanPort *inputLoop;
	QCBooleanPort *inputTrig;

	QCNumberPort *inputCurrentVolume;
	QCNumberPort *inputCurrentPosition;

	QCBooleanPort *inputSynchronous;

	NSMutableArray *_allocatedSounds;
	BOOL _executedSinceSetup;
}

- (id)initWithIdentifier:(id)fp8;

- (void)setFile:(NSString*)file;
- (BOOL)setup:(QCOpenGLContext *)context;
- (void)cleanup:(QCOpenGLContext *)context;

- (void)enable:(QCOpenGLContext *)context;
- (void)disable:(QCOpenGLContext *)context;

- (BOOL)execute:(QCOpenGLContext *)context time:(double)time arguments:(NSDictionary *)arguments;

- (void)_startPlayingThread:(NSSound*)s;
- (void)_startPlaying;
@end