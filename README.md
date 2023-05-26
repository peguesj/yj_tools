# Vocal Remover Script

This is a Python script for removing vocals from an audio file. It uses the Hybrid Demucs or Spleeter library, depending on the command-line arguments.

## Requirements

You will need Python 3.8 or later. You will also need the following Python libraries:

- demucs
- spleeter

You can install these libraries using pip:

```bash
pip install demucs spleeter
```

## Usage

To use this script, run it from the command line and provide the path to the audio file as an argument:

```bash
python vocal_remover.py path/to/audio/file
```

By default, this script uses the Hybrid Demucs library to remove vocals. The script will output a new audio file with the same name as the input file, appended with `_NoVocals` before the file extension. This file will be located in the same directory as the original audio file.

If you want to use the Spleeter library instead, add the `-alt` flag:

```bash
python vocal_remover.py -alt path/to/audio/file
```

## Limitations and Notes

This script may not always produce perfect results. The quality of separation can depend on a number of factors, including the complexity of the audio and the quality of the original recording. Additionally, while Hybrid Demucs and Spleeter are powerful tools for audio separation, they can sometimes produce artifacts or other imperfections in the output audio.
```
---
