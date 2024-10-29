"""
Text Splitting Script

Description:
This script is designed to efficiently manage long text inputs by splitting them into segments that do not exceed a specified maximum length. It first attempts to split the text based on sentence-ending punctuation (periods, question marks, and exclamation points). If any resulting segments still exceed the maximum length, the script then attempts to split these segments further using commas as delimiters. If segments remain too long after attempting to split by commas, a final pass splits them by spaces.

Usage:
The script requires two command-line arguments: 
1. The maximum allowable length for any single segment.
2. The text to be split.

The script outputs each segment on a new line, making it suitable for processing in other tools or scripts that require pre-segmented text.

Example Command Line:
python speech_text_splitter.py "Your long text here that needs to be processed into manageable segments." 100
"""

import sys
import re


def split_text(text, max_length):
    # Helper function to recursively split the text based on provided delimiter
    def split_by_delimiter(sentences, delimiter, final=False):
        new_sentences = []
        for sentence in sentences:
            # Only attempt to split if sentence is longer than max_length
            if len(sentence) > max_length:
                parts = sentence.split(delimiter)
                temp_sentence = ""
                for part in parts:
                    if len(temp_sentence) + len(part) + len(delimiter) <= max_length:
                        temp_sentence += (delimiter if temp_sentence else "") + part
                    else:
                        if temp_sentence:
                            new_sentences.append(temp_sentence)
                        temp_sentence = part
                # Add the last gathered part if not empty
                if temp_sentence:
                    new_sentences.append(temp_sentence)
            else:
                new_sentences.append(sentence)
        if final:  # Final pass: split by space if still too long
            return [subpart for sentence in new_sentences for subpart in split_by_space(sentence, max_length)]
        return new_sentences

    # Split by spaces as a last resort
    def split_by_space(sentence, max_length):
        # Split only if the sentence is too long
        if len(sentence) <= max_length:
            return [sentence]
        else:
            parts = []
            while len(sentence) > max_length:
                space_index = sentence.rfind(' ', 0, max_length)
                if space_index == -1:  # No space found, split at max_length
                    parts.append(sentence[:max_length])
                    sentence = sentence[max_length:]
                else:
                    parts.append(sentence[:space_index])
                    sentence = sentence[space_index+1:]
            parts.append(sentence)
            return parts

    # Initial split by sentence-ending punctuation
    sentences = re.split(r'(?<=[.!?])\s+', text)
    sentences = split_by_delimiter(sentences, ', ')
    return split_by_delimiter(sentences, ' ', final=True)
    
    
if __name__ == "__main__":
    input_text = sys.argv[2]
    max_length = int(sys.argv[1])

    for line in split_text(input_text, max_length):
        print(line)

