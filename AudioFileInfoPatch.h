@interface AudioFileInfoPatch : QCPatch
{
    QCStringPort *inputPath;

	QCBooleanPort *outputFileLoaded;
	QCNumberPort *outputDuration;
}

- (BOOL)execute:(QCOpenGLContext *)context time:(double)time arguments:(NSDictionary *)arguments;
@end