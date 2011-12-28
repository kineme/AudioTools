@interface AudioDeviceInfoPatch : QCPatch
{
    QCStructurePort *outputInputDevices;
    QCStructurePort *outputOutputDevices;
}

- (void)enable:(QCOpenGLContext *)context;

@end