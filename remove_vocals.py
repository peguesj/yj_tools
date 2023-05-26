import sys
import os
from spleeter.separator import Separator
from pydub import AudioSegment

def remove_vocals(input_file):
    # Define separator
    separator = Separator('spleeter:2stems')

    # Separate audio
    output_folder = 'spleeter_output'
    separator.separate_to_file(input_file, output_folder)

    # The output is in a sub-folder named after the input file (without extension)
    base_file_name = os.path.basename(input_file)
    base_name_no_ext = os.path.splitext(base_file_name)[0]
    output_subfolder = os.path.join(output_folder, base_name_no_ext)

    # The accompaniment is saved in a file named "accompaniment.wav"
    output_file = os.path.join(output_subfolder, 'accompaniment.wav')

    # Convert the output file to the same format as the input file
    output_audio = AudioSegment.from_wav(output_file)
    final_output_file = os.path.splitext(input_file)[0] + '_NoVocals' + os.path.splitext(input_file)[1]
    output_audio.export(final_output_file, format=os.path.splitext(input_file)[1].replace('.', ''))

    print(f'Vocal removed audio file has been saved as: {final_output_file}')


if __name__ == "__main__":
    input_file = sys.argv[1]
    remove_vocals(input_file)

