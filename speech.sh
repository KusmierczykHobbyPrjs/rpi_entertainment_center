#!/bin/bash

# Reads text passed as an argument using google translate
# Pass language code as the first argument


# Check for volume environment variable, default to 100 if not set
VOLUME_LEVEL=${VOLUME:-100}

# Convert volume from percentage (0-100) to scale (0-32768)
VOLUME_SCALE=$((VOLUME_LEVEL * 32768 / 100))


# List of valid ISO 639-1 language codes
VALID_LANG_CODES="af ar az be bg bn bs ca cs cy da de el en es et eu fa fi fr gl gu he hi hr ht hu hy id is it ja ka kn ko la lt lv mk ml mr ms mt nl no pl pt ro ru sk sl sq sr sv sw ta te th tl tr uk ur vi zh"

# Check if the first argument is a valid language code
LANG_CODE="en" # Default to English
for code in $VALID_LANG_CODES; do
  if [[ "$1" == "$code" ]]; then
    LANG_CODE=$1
    shift # Remove the first argument since it's used as a language code
    break
  fi
done


INPUT="$*" # All remaining arguments are considered as input

# Split the input into manageable parts using the Python script
MAX_LENGTH=150 # Maximum length of text segments
IFS=$'\n' # Change internal field separator to new line
parts=($(python3 speech_text_splitter.py $MAX_LENGTH "$INPUT" ))


for part in "${parts[@]}"
  do
    NEXTURL=$(echo $part | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
    #echo "$NEXTURL"
    mpg123 -q -b 100 -f $VOLUME_SCALE "http://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&q=$NEXTURL&tl=$LANG_CODE"
done
