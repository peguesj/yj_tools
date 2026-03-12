# __init__.py for @yj/tran
"""
TranscriptAnalysis - Unified transcript analysis package
Author: Jeremiah Pegues <jeremiah@pegues.io>
Version: 1.0.0

This package provides advanced transcript analysis, TUI, and OpenAI integration.
"""

from .extract_insights_clean import TranscriptInsightExtractor, TopicDiscussion, SpeakerInsight, SentimentAnalysis, Diarization
from .openai_client import OpenAIClient

__version__ = "1.0.0"
__author__ = "Jeremiah Pegues <jeremiah@pegues.io>"
__title__ = "TranscriptAnalysis"

# CLI/TUI entrypoint helpers
import sys
import os

def tui():
    from .transcript_analyzer_tui import TranscriptAnalyzerTUI
    TranscriptAnalyzerTUI().run()

def parse():
    from .parse_transcript import main as parse_main
    parse_main()

# Expose CLI entrypoints for yj_tran_tui and yj_tran_parse
if __name__ == "__main__":
    if sys.argv and sys.argv[0].endswith("tui"):
        tui()
    elif sys.argv and sys.argv[0].endswith("parse"):
        parse()
