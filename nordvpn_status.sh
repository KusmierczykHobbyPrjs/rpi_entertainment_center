#!/bin/bash

source config.sh

STATUS=`nordvpn status`
STATUS="${STATUS//$'\n'/. }"
bash speech_en.sh $STATUS

