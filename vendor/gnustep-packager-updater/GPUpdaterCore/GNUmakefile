# A static archive, linked into the app (set before common.make reads it);
# position-independent, so the test bundles can link it too.
shared = no

include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = GPUpdaterCore

GPUpdaterCore_OBJC_FILES = Source/GPUpdater.m Source/GPUpdaterDownload.m
GPUpdaterCore_C_FILES = Source/GPUpdaterWinHTTP.c
GPUpdaterCore_CPPFLAGS += -IHeaders

ADDITIONAL_OBJCFLAGS += -fPIC
ADDITIONAL_CFLAGS += -fPIC

include $(GNUSTEP_MAKEFILES)/library.make
