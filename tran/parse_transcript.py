#!/usr/bin/env python3
"""
Transcript Parser Script
Converts the meeting transcript format to structured JSON

Pattern Analysis:
- Speaker Name: "Isaiah Pegues" or "Jeremiah Pegues" (on its own line)
- DateTime: "Today, H:MM AM/PM" (on its own line)
- Message Body: Everything until the next speaker name (may span multiple lines)
"""

import re
import json
from datetime import datetime
from typing import List, Dict, Any

def parse_transcript(file_path: str) -> List[Dict[str, Any]]:
    """
    Parse the transcript file and return a list of structured message objects.
    
    Returns:
        List of dictionaries with keys: speaker, datetime, message
    """
    
    # Read the file content
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Remove the first line (filepath comment) if it exists
    lines = content.strip().split('\n')
    if lines[0].startswith('//'):
        lines = lines[1:]
    
    # Regex patterns
    speaker_pattern = r'^([A-Z][a-z]+ [A-Z][a-z]+)$'
    datetime_pattern = r'^Today, (\d{1,2}:\d{2} [AP]M)$'
    
    messages = []
    current_speaker = None
    current_datetime = None
    current_message_lines = []
    
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        
        # Check if this line is a speaker name
        speaker_match = re.match(speaker_pattern, line)
        if speaker_match:
            # Save previous message if we have one
            if current_speaker and current_datetime and current_message_lines:
                message_text = '\n'.join(current_message_lines).strip()
                if message_text:  # Only add non-empty messages
                    messages.append({
                        'speaker': current_speaker,
                        'datetime': current_datetime,
                        'message': message_text,
                        'timestamp': f"2025-06-12 {current_datetime}"  # Adding full timestamp for sorting
                    })
            
            # Start new message
            current_speaker = speaker_match.group(1)
            current_message_lines = []
            current_datetime = None
            
            # Next line should be datetime
            if i + 1 < len(lines):
                next_line = lines[i + 1].strip()
                datetime_match = re.match(datetime_pattern, next_line)
                if datetime_match:
                    current_datetime = datetime_match.group(1)
                    i += 2  # Skip both speaker and datetime lines
                    continue
            
        # If we have a current speaker and datetime, this is part of the message
        elif current_speaker and current_datetime:
            current_message_lines.append(line)
        
        i += 1
    
    # Don't forget the last message
    if current_speaker and current_datetime and current_message_lines:
        message_text = '\n'.join(current_message_lines).strip()
        if message_text:
            messages.append({
                'speaker': current_speaker,
                'datetime': current_datetime,
                'message': message_text,
                'timestamp': f"2025-06-12 {current_datetime}"
            })
    
    return messages

def convert_to_json(messages: List[Dict[str, Any]], output_file: str) -> None:
    """
    Convert the parsed messages to a structured JSON format and save to file.
    """
    
    # Create structured output
    output = {
        'meeting_info': {
            'date': '2025-06-12',
            'participants': list(set(msg['speaker'] for msg in messages)),
            'total_messages': len(messages),
            'duration_estimate': f"{len(messages) * 1.5:.1f} minutes"  # Rough estimate
        },
        'conversation': messages
    }
    
    # Save to JSON file
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    
    print(f"✅ Successfully parsed {len(messages)} messages")
    print(f"📄 Output saved to: {output_file}")
    print(f"👥 Participants: {', '.join(output['meeting_info']['participants'])}")

def main():
    """Main function to run the transcript parser."""
    
    # File paths
    input_file = '/Users/jeremiah/Developer/vantage-evo/250612_pegsys.meeting.transcript.json'
    output_file = '/Users/jeremiah/Developer/vantage-evo/parsed_transcript.json'
    
    print("🔍 Parsing transcript...")
    print(f"📖 Input file: {input_file}")
    
    try:
        # Parse the transcript
        messages = parse_transcript(input_file)
        
        # Convert to JSON
        convert_to_json(messages, output_file)
        
        # Show some sample messages
        print(f"\n📋 Sample messages:")
        for i, msg in enumerate(messages[:3]):
            print(f"\n{i+1}. {msg['speaker']} at {msg['datetime']}:")
            preview = msg['message'][:100] + "..." if len(msg['message']) > 100 else msg['message']
            print(f"   {preview}")
    
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    main()
