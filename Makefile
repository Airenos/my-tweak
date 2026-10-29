TARGET := iphone:clang:latest:14.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ETAlienSpeedup
ETAlienSpeedup_FILES = ETAlienSpeedup.m
ETAlienSpeedup_CFLAGS = -fobjc-arc -O3
ETAlienSpeedup_FRAMEWORKS = Foundation UIKit AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
