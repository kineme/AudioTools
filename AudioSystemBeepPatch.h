@interface AudioSystemBeepPatch : QCPatch
{
    QCBooleanPort *inputTrigger;
}

- (id)initWithIdentifier:(id)fp8;

- (BOOL)execute:(QCOpenGLContext *)context time:(double)time arguments:(NSDictionary *)arguments;
@end