#!/usr/bin/env python

import RPi.GPIO as GPIO
import subprocess
import sys
import time

# Executes a command when GPIO slope is detected

# default: shutdown at gpio pin=3
BCM_GPIO_NO = 3
CMD = ['shutdown', 'now']

# parse from args
try:
    BCM_GPIO_NO = int(sys.argv[1])
    CMD = sys.argv[2:]
    print("[gpio2command] Mapping GPIO=%d to CMD=%s" % (BCM_GPIO_NO, CMD))
except:
    print("[gpio2command] Executes a command when GPIO slope is detected e.g. a selected button is pressed.")
    print("[gpio2command] No argument passed. Default GPIO=%d used. CMD=%s" % (BCM_GPIO_NO, CMD))

# setup
GPIO.setmode(GPIO.BCM)
GPIO.setup(BCM_GPIO_NO, GPIO.IN, pull_up_down=GPIO.PUD_UP)

last_time = 0

def execute_cmd(*args, **kwargs):
    # at least 1s of delay between taking action
    global last_time
    if time.time()-last_time<=1: return 
    last_time = time.time()
    
    print("[gpio2command] Button GPIO=%d pressed. Executing: %s" % (BCM_GPIO_NO, CMD))
    subprocess.call(CMD, shell=False)

#GPIO.wait_for_edge(BCM_GPIO_NO, GPIO.FALLING)
GPIO.add_event_detect(BCM_GPIO_NO, GPIO.FALLING, callback=execute_cmd)  # add rising edge detection on a channel

# keep waiting forever
while True: 
    time.sleep(1000)

