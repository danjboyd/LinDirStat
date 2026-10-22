# A static archive, linked into the app (set before common.make reads it);
# position-independent, so the test bundles can link it too.
shared = no

include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_NAME = GPUpdaterUI

GPUpdaterUI_OBJC_FILES = Source/GPStandardUpdaterController.m
# ShellExecuteW for opening URLs on Windows; empty elsewhere.
GPUpdaterUI_C_FILES = Source/GPUpdaterUIShell.c
GPUpdaterUI_CPPFLAGS += -IHeaders -I../GPUpdaterCore/Headers

ADDITIONAL_OBJCFLAGS += -fPIC
ADDITIONAL_CFLAGS += -fPIC

include $(GNUSTEP_MAKEFILES)/library.make
