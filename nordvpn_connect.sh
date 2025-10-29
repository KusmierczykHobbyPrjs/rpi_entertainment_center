#!/bin/bash

source config.sh

bash signal_action.sh &

nordvpn connect $1

