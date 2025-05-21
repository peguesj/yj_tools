import argparse
import os
import subprocess
from spleeter.separator import Separator

def remove_vocals(input_path, use_spleeter):
    # Get the base path, filename, and extension
    base_path, filename = os.path.split(input_path)
    file_base, file_ext = os.path.splitext(filename)

    # Construct the output path
    output_path = os.path.join(base_path, f"{file_base}_NoVocals{file_ext}")

    # Depending on the flag, use either Demucs or Spleeter
    if use_spleeter:
        separator = Separator('spleeter:2stems')
        separator.separate_to_file(input_path, base_path, filename_format='{filename}/{instrument}{extension}')
        
        # The vocals will be in a file named {file_base}/vocals{file_ext}, remove it
        os.remove(os.path.join(base_path, file_base, 'vocals' + file_ext))
        
        # Rename the accompaniment to the desired output filename
        os.rename(os.path.join(base_path, file_base, 'accompaniment' + file_ext), output_path)
        
        # Remove the created directory
        os.rmdir(os.path.join(base_path, file_base))
    else:
        # Use Demucs
        subprocess.run(['demucs', '-n', 'htdemucs_ft', '--two-stems=other', input_path])

        # The other track will be in a directory named separated/htdemucs_ft/{file_base}/{file_base}_other.wav
        # Move it to the desired output filename
        os.rename(os.path.join('separated', 'htdemucs_ft', file_base, f'{file_base}_other.wav'), output_path)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Remove vocals from an audio file.")
    parser.add_argument('input_path', type=str, help="The path to the audio file.")
    parser.add_argument('-alt', action='store_true', help="Use Spleeter instead of Hybrid Demucs.")

    args = parser.parse_args()

    remove_vocals(args.input_path, args.alt)
