#!/usr/bin/env python3
"""
Interactive TUI for Transcript Analysis
A beautiful terminal interface for querying meeting transcript insights.
"""

import json
import os
import sys
import asyncio
from datetime import datetime
from typing import Dict, List, Any, Optional
from openai import AzureOpenAI
from dataclasses import asdict
import threading
import time
from rich.spinner import Spinner
import logging
from pathlib import Path

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.layout import Layout
from rich.text import Text
from rich.prompt import Prompt, Confirm, IntPrompt
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.tree import Tree
from rich.columns import Columns
from rich.align import Align
from rich.rule import Rule
from rich.syntax import Syntax
from rich.markdown import Markdown
from rich import box
from rich.live import Live

# Import our insight extraction classes
from extract_insights_clean import TranscriptInsightExtractor, TopicDiscussion, SpeakerInsight, SentimentAnalysis, Diarization

class TranscriptAnalyzerTUI:
    def __init__(self):
        self.console = Console()
        self.extractor = None
        self.topics: list[TopicDiscussion] = []
        self.insights: list[SpeakerInsight] = []
        self.sentiment_analysis: Optional[SentimentAnalysis] = None
        self.diarization: list[Diarization] = []
        self.extraction_error = None
        self._extraction_done = threading.Event()
        # Load AI analysis default instructions and overrides
        self.ai_default_instructions = self._load_file_content('ai-analysis_default_instructions')
        self.ai_overrides = self._load_file_content('ai-analysis_overrides')
        # Use unified OpenAIClient for all AI calls (batching best practice)
        from openai_client import OpenAIClient
        self.client = OpenAIClient()
        self.logger = logging.getLogger("TranscriptAnalyzerTUI")
        logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s: %(message)s")
        # Extraction will be batched and cached
        self._extraction_done = threading.Event()

    def _load_file_content(self, filename):
        try:
            with open(os.path.join(os.path.dirname(__file__), filename), 'r', encoding='utf-8') as f:
                return f.read().strip()
        except Exception as e:
            self.logger.warning(f"Could not load {filename}: {e}")
            return ""

    def show_welcome(self):
        """Display welcome screen with ASCII art and instructions."""
        welcome_text = """
╔══════════════════════════════════════════════════════════════════════════════╗
║                    📊 TRANSCRIPT INSIGHT ANALYZER 📊                        ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  Advanced AI-Powered Meeting Transcript Analysis & Query Interface          ║
║                                                                              ║
║  Features:                                                                   ║
║  • 🎯 Topic Extraction & Classification                                     ║
║  • 🧠 Speaker Insights & Communication Analysis                             ║
║  • 💭 Sentiment Analysis (Overall, Speaker, Topic-specific)                 ║
║  • 🗣️  Diarization & Speaking Pattern Analysis                              ║
║  • 🤖 AI-Powered Natural Language Queries                                   ║
║  • 📈 Interactive Data Visualization                                        ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
        """
        
        self.console.print(Panel(
            welcome_text,
            border_style="bright_blue",
            padding=(1, 2)
        ))

    async def load_transcript_async(self, transcript_path):
        self.extractor = None
        self.topics = []
        self.insights = []
        self.sentiment_analysis = None
        self.diarization = []
        self.extraction_error = None
        loop = asyncio.get_event_loop()
        try:
            # Step 1: Upload transcript file to OpenAI for RAG
            transcript_file_id = None
            upload_file_fn = getattr(self.client, 'upload_file', None)
            if upload_file_fn:
                upload_result = await loop.run_in_executor(None, lambda: upload_file_fn(transcript_path, purpose="assistants"))
                transcript_file_id = getattr(upload_result, 'id', None)
            # Step 2: Create Assistant and Thread (if available)
            create_assistant_fn = getattr(self.client, 'create_assistant', None)
            create_thread_fn = getattr(self.client, 'create_thread', None)
            create_run_fn = getattr(self.client, 'create_run', None)
            retrieve_run_fn = getattr(self.client, 'retrieve_run', None)
            list_messages_fn = getattr(self.client, 'list_messages', None)
            if create_assistant_fn and create_thread_fn and create_run_fn and retrieve_run_fn and list_messages_fn:
                assistant = await loop.run_in_executor(None, lambda: create_assistant_fn(
                    name="Transcript Insight Assistant",
                    instructions="You are an expert meeting transcript analyst. Given a transcript file, extract: 1) topics discussed, 2) speaker insights, 3) sentiment analysis, 4) diarization and speaking patterns. Return all results as a single JSON object with keys: topics_discussed, speaker_insights, sentiment_analysis, diarization. Use the transcript file for all context.",
                    tools=[{"type": "retrieval"}],
                    file_ids=[transcript_file_id] if transcript_file_id else None,
                    model=getattr(self.client, 'deployment', 'gpt-4.1-mini')
                ))
                assistant_id = getattr(assistant, 'id', None)
                thread = await loop.run_in_executor(None, lambda: create_thread_fn())
                thread_id = getattr(thread, 'id', None)
                # Step 3: Submit a single run to the Assistant for all analyses
                run = await loop.run_in_executor(None, lambda: create_run_fn(
                    thread_id,
                    assistant_id=assistant_id,
                    instructions="Analyze the transcript and return a single JSON object with keys: topics_discussed, speaker_insights, sentiment_analysis, diarization."
                ))
                run_id = getattr(run, 'id', None)
                # Wait for run to complete
                status = getattr(run, 'status', None)
                while status not in ("completed", "failed", "cancelled"):
                    await asyncio.sleep(2)
                    run = await loop.run_in_executor(None, lambda: retrieve_run_fn(thread_id, run_id))
                    status = getattr(run, 'status', None)
                if status == "completed":
                    # Get the latest message from the thread
                    messages = await loop.run_in_executor(None, lambda: list_messages_fn(thread_id))
                    if hasattr(messages, 'data') and messages.data:
                        content = messages.data[0].content[0].text.value
                        insights = json.loads(content)
                        self.topics = [TopicDiscussion(**t) for t in insights['topics_discussed']]
                        self.insights = [SpeakerInsight(**i) for i in insights['speaker_insights']]
                        self.sentiment_analysis = SentimentAnalysis(**insights['sentiment_analysis'])
                        self.diarization = [Diarization(**d) for d in insights['diarization']]
                        return
                self.extraction_error = f"Assistant run failed or incomplete (status: {status})"
            else:
                # Fallback: Use legacy extraction if Assistants API is not available
                try:
                    from extract_insights_clean import TranscriptInsightExtractor
                    self.extractor = TranscriptInsightExtractor(transcript_path)
                    insights = await loop.run_in_executor(None, self.extractor.extract_comprehensive_insights)
                    self.topics = [TopicDiscussion(**t) for t in insights['topics_discussed']]
                    self.insights = [SpeakerInsight(**i) for i in insights['speaker_insights']]
                    self.sentiment_analysis = SentimentAnalysis(**insights['sentiment_analysis'])
                    self.diarization = [Diarization(**d) for d in insights['diarization']]
                except Exception as fallback_e:
                    self.extractor = None
                    self.topics = []
                    self.insights = []
                    self.sentiment_analysis = None
                    self.diarization = []
                    self.extraction_error = f"Assistants API and legacy extraction failed: {fallback_e}"
        except Exception as e:
            self.extractor = None
            self.topics = []
            self.insights = []
            self.sentiment_analysis = None
            self.diarization = []
            self.extraction_error = str(e)

    def load_transcript(self, transcript_path):
        """Async wrapper for transcript loading, for TUI compatibility."""
        self._extraction_done.clear()
        def run_async():
            asyncio.run(self._load_transcript_and_set_event(transcript_path))
        thread = threading.Thread(target=run_async, daemon=True)
        thread.start()
        with self.console.status("[bold green]Extracting topics and insights...", spinner="dots") as status:
            while not self._extraction_done.is_set():
                time.sleep(0.1)
        if self.extraction_error:
            self.console.print(f"[bold red]Extraction failed: {self.extraction_error}")
            return False
        return True

    async def _load_transcript_and_set_event(self, transcript_path):
        await self.load_transcript_async(transcript_path)
        self._extraction_done.set()

    def show_main_menu(self):
        """Display the main menu options."""
        menu_panel = Panel(
            """[bold cyan]MAIN MENU[/bold cyan]
            
[bright_blue]1.[/bright_blue] 📊 View Analysis Overview
[bright_blue]2.[/bright_blue] 🎯 Browse Topics
[bright_blue]3.[/bright_blue] 🧠 Speaker Insights
[bright_blue]4.[/bright_blue] 💭 Sentiment Analysis
[bright_blue]5.[/bright_blue] 🗣️ Diarization Analysis
[bright_blue]6.[/bright_blue] 🔍 Search & Query
[bright_blue]7.[/bright_blue] 🤖 AI-Powered Query
[bright_blue]8.[/bright_blue] 📁 Export Results
[bright_blue]9.[/bright_blue] ❌ Exit

Choose an option (1-9):""",
            border_style="green",
            padding=(1, 1)
        )
        
        self.console.print(menu_panel)

    def show_analysis_overview(self):
        """Display high-level analysis overview."""
        if self.extraction_error:
            self.console.print(f"[bold red]Cannot show overview: Extraction failed: {self.extraction_error}")
            return
        if not self.topics and not self.insights:
            self.console.print("[yellow]No analysis data available. Please load a transcript.")
            return
        
        # Create layout with multiple panels
        layout = Layout()
        layout.split_column(
            Layout(name="header", size=3),
            Layout(name="body"),
            Layout(name="footer", size=3)
        )
        
        layout["body"].split_row(
            Layout(name="left"),
            Layout(name="right")
        )
        
        # Header
        layout["header"].update(Panel(
            "[bold cyan]📊 ANALYSIS OVERVIEW[/bold cyan]",
            style="bold blue"
        ))
        
        # Meeting info
        meeting_info = None
        if self.extractor and hasattr(self.extractor, 'transcript_data') and self.extractor.transcript_data:
            meeting_info = self.extractor.transcript_data.get('meeting_info', {})
        if not meeting_info:
            meeting_info = {'date': 'N/A', 'participants': [], 'total_messages': 0, 'duration_estimate': 'N/A'}
        info_table = Table(title="Meeting Information", box=box.ROUNDED)
        info_table.add_column("Metric", style="cyan")
        info_table.add_column("Value", style="white")
        
        info_table.add_row("Date", meeting_info.get('date', 'N/A'))
        info_table.add_row("Participants", ", ".join(meeting_info.get('participants', [])))
        info_table.add_row("Total Messages", str(meeting_info.get('total_messages', 0)))
        info_table.add_row("Estimated Duration", f"{meeting_info.get('duration_estimate', 'N/A')} minutes")
        info_table.add_row("Topics Identified", str(len(self.topics)))
        info_table.add_row("Speaker Insights", str(len(self.insights)))
        
        layout["left"].update(Panel(info_table, border_style="green"))
        
        # Topic breakdown
        topic_table = Table(title="Topic Breakdown", box=box.ROUNDED)
        topic_table.add_column("Category", style="cyan")
        topic_table.add_column("Count", style="white")
        topic_table.add_column("Avg Duration", style="yellow")
        
        # Group topics by category
        category_stats = {}
        for topic in self.topics:
            cat = topic.category
            if cat not in category_stats:
                category_stats[cat] = {'count': 0, 'total_duration': 0}
            category_stats[cat]['count'] += 1
            category_stats[cat]['total_duration'] += topic.duration_minutes
        
        for category, stats in category_stats.items():
            avg_duration = stats['total_duration'] / stats['count']
            topic_table.add_row(
                category.title(),
                str(stats['count']),
                f"{avg_duration:.1f} min"
            )
        
        layout["right"].update(Panel(topic_table, border_style="green"))
        
        # Footer with overall sentiment
        overall_sentiment = self.sentiment_analysis.overall_sentiment.replace('_', ' ').title() if self.sentiment_analysis else 'N/A'
        layout["footer"].update(Panel(
            f"[bold]Overall Sentiment:[/bold] [green]{overall_sentiment}[/green] | "
            f"[bold]Confidence:[/bold] {self.sentiment_analysis.confidence:.2f}" if self.sentiment_analysis else "[bold]Sentiment Analysis:[/bold] N/A",
            style="dim"
        ))
        
        self.console.print(layout)

    def browse_topics(self):
        """Interactive topic browser."""
        if not self.topics:
            self.console.print("❌ [red]No topics available[/red]")
            return
        
        while True:
            self.console.clear()
            self.console.print(Panel(
                "[bold cyan]🎯 TOPIC BROWSER[/bold cyan]",
                style="bold blue"
            ))
            
            # Display topics table
            topics_table = Table(box=box.ROUNDED)
            topics_table.add_column("#", style="cyan", width=3)
            topics_table.add_column("Title", style="white", width=40)
            topics_table.add_column("Category", style="yellow", width=12)
            topics_table.add_column("Duration", style="green", width=10)
            topics_table.add_column("Messages", style="blue", width=8)
            topics_table.add_column("Speakers", style="magenta", width=15)
            
            for i, topic in enumerate(self.topics, 1):
                speakers_str = ", ".join(topic.speakers)
                if len(speakers_str) > 13:
                    speakers_str = speakers_str[:10] + "..."
                
                topics_table.add_row(
                    str(i),
                    topic.title,
                    topic.category.title(),
                    f"{topic.duration_minutes:.1f}m",
                    str(topic.message_count),
                    speakers_str
                )
            
            self.console.print(topics_table)
            
            choice = Prompt.ask(
                "\n[cyan]Enter topic number to view details, 'b' to go back[/cyan]",
                default="b"
            )
            
            if choice.lower() == 'b':
                break
            elif choice.isdigit() and 1 <= int(choice) <= len(self.topics):
                self._show_topic_details(self.topics[int(choice) - 1])
            else:
                self.console.print("❌ [red]Invalid choice[/red]")
                input("Press Enter to continue...")

    def _show_topic_details(self, topic: TopicDiscussion):
        """Show detailed view of a specific topic."""
        self.console.clear()
        
        # Create detailed topic panel
        detail_text = f"""[bold cyan]📋 Topic Details[/bold cyan]

[bold]Title:[/bold] {topic.title}
[bold]Category:[/bold] {topic.category.title()} > {topic.subcategory}
[bold]Duration:[/bold] {topic.duration_minutes:.1f} minutes ({topic.start_time} - {topic.end_time})
[bold]Messages:[/bold] {topic.message_count}
[bold]Speakers:[/bold] {", ".join(topic.speakers)}
[bold]Context Score:[/bold] {topic.context_score:.2f}

[bold yellow]🏷️ Tags:[/bold yellow]
{", ".join(topic.tags)}

[bold green]🔑 Key Points:[/bold green]"""
        
        for point in topic.key_points:
            detail_text += f"\n• {point}"
        
        if topic.decisions:
            detail_text += "\n\n[bold blue]✅ Decisions Made:[/bold blue]"
            for decision in topic.decisions:
                detail_text += f"\n• {decision}"
        
        if topic.action_items:
            detail_text += "\n\n[bold red]📋 Action Items:[/bold red]"
            for item in topic.action_items:
                detail_text += f"\n• {item}"
        
        self.console.print(Panel(detail_text, border_style="cyan", padding=(1, 2)))
        
        input("\nPress Enter to continue...")

    def show_speaker_insights(self):
        """Display speaker insights analysis."""
        if self.extraction_error:
            self.console.print(f"[bold red]Cannot show speaker insights: Extraction failed: {self.extraction_error}")
            return
        if not self.insights:
            self.console.print("[yellow]No speaker insights available.")
            return
        
        self.console.clear()
        self.console.print(Panel(
            "[bold cyan]🧠 SPEAKER INSIGHTS[/bold cyan]",
            style="bold blue"
        ))
        
        # Group insights by speaker
        speaker_groups = {}
        for insight in self.insights:
            if insight.speaker not in speaker_groups:
                speaker_groups[insight.speaker] = []
            speaker_groups[insight.speaker].append(insight)
        
        for speaker, insights in speaker_groups.items():
            # Create speaker panel
            speaker_tree = Tree(f"[bold blue]{speaker}[/bold blue] ({len(insights)} insights)")
            
            for insight in insights:
                insight_node = speaker_tree.add(f"[cyan]{insight.insight}[/cyan]")
                insight_node.add(f"[dim]Confidence: {insight.confidence_score:.2f}[/dim]")
                insight_node.add(f"[dim]Sentiment: {insight.sentiment}[/dim]")
                insight_node.add(f"[dim]Expertise: {insight.expertise_level}[/dim]")
                insight_node.add(f"[dim]Engagement: {insight.engagement_level}[/dim]")
                
                if insight.tags:
                    insight_node.add(f"[dim]Tags: {', '.join(insight.tags)}[/dim]")
            
            self.console.print(Panel(speaker_tree, border_style="green"))
        
        input("\nPress Enter to continue...")

    def show_sentiment_analysis(self):
        """Display comprehensive sentiment analysis."""
        if self.extraction_error:
            self.console.print(f"[bold red]Cannot show sentiment analysis: Extraction failed: {self.extraction_error}")
            return
        if not self.sentiment_analysis:
            self.console.print("[yellow]No sentiment analysis available.")
            return
        
        self.console.clear()
        self.console.print(Panel(
            "[bold cyan]💭 SENTIMENT ANALYSIS[/bold cyan]",
            style="bold blue"
        ))
        
        # Overall sentiment
        overall_panel = Panel(
            f"[bold]Overall Meeting Sentiment:[/bold] [green]{getattr(self.sentiment_analysis, 'overall_sentiment', 'N/A').replace('_', ' ').title()}[/green]\n"
            f"[bold]Confidence:[/bold] {getattr(self.sentiment_analysis, 'confidence', 0.0):.2f}\n"
            f"[bold]Emotional Intensity:[/bold] {getattr(self.sentiment_analysis, 'emotional_intensity', 0.0):.2f}",
            title="📊 Overall Analysis",
            border_style="blue"
        )
        self.console.print(overall_panel)
        
        # Speaker sentiment breakdown
        speaker_table = Table(title="👥 Speaker Sentiment Breakdown", box=box.ROUNDED)
        speaker_table.add_column("Speaker", style="cyan")
        speaker_table.add_column("Sentiment", style="white")
        speaker_table.add_column("Polarity", style="green")
        speaker_table.add_column("Subjectivity", style="yellow")
        speaker_table.add_column("Intensity", style="red")
        speaker_table.add_column("Messages", style="blue")
        speaker_sentiments = getattr(self.sentiment_analysis, 'speaker_sentiments', {})
        for speaker, data in speaker_sentiments.items():
            speaker_table.add_row(
                speaker,
                data.get('overall_sentiment', 'N/A').replace('_', ' ').title(),
                f"{data.get('polarity', 0.0):.2f}",
                f"{data.get('subjectivity', 0.0):.2f}",
                f"{data.get('emotional_intensity', 0.0):.2f}",
                str(data.get('message_count', 0))
            )
        self.console.print(speaker_table)
        
        input("\nPress Enter to continue...")

    def show_diarization_analysis(self):
        """Display diarization and speaking pattern analysis."""
        if self.extraction_error:
            self.console.print(f"[bold red]Cannot show diarization: Extraction failed: {self.extraction_error}")
            return
        if not self.diarization:
            self.console.print("[yellow]No diarization data available.")
            return
        
        self.console.clear()
        self.console.print(Panel(
            "[bold cyan]🗣️ DIARIZATION ANALYSIS[/bold cyan]",
            style="bold blue"
        ))
        
        # Create diarization table
        diar_table = Table(title="Speaking Pattern Analysis", box=box.ROUNDED)
        diar_table.add_column("Speaker", style="cyan")
        diar_table.add_column("Speaking %", style="green")
        diar_table.add_column("Total Words", style="white")
        diar_table.add_column("Avg Message Length", style="yellow")
        diar_table.add_column("Questions", style="blue")
        diar_table.add_column("Interruptions", style="red")
        diar_table.add_column("Communication Style", style="magenta")
        diar_table.add_column("Technical Score", style="bright_blue")
        
        for speaker_data in self.diarization:
            diar_table.add_row(
                getattr(speaker_data, 'speaker', 'N/A'),
                f"{getattr(speaker_data, 'speaking_percentage', 0.0):.1f}%",
                str(getattr(speaker_data, 'total_words', 0)),
                f"{getattr(speaker_data, 'average_message_length', 0.0):.1f}",
                str(getattr(speaker_data, 'question_count', 0)),
                str(getattr(speaker_data, 'interruption_count', 0)),
                getattr(speaker_data, 'communication_style', 'N/A'),
                f"{getattr(speaker_data, 'technical_vocabulary_score', 0.0):.2f}"
            )
        
        self.console.print(diar_table)
        
        # Show dominant topics per speaker
        self.console.print("\n[bold yellow]🎯 Dominant Topics by Speaker:[/bold yellow]")
        for speaker_data in self.diarization:
            topics_str = ", ".join(getattr(speaker_data, 'dominant_topics', [])[:3])
            self.console.print(f"[cyan]{getattr(speaker_data, 'speaker', 'N/A')}: [/cyan]{topics_str}")
        
        input("\nPress Enter to continue...")

    def ai_assistant_session(self):
        """Interactive OpenAI assistant session for recursive, context-aware analysis and refinement."""
        import traceback
        from rich.prompt import Prompt
        self.console.clear()
        self.console.print(Panel(
            "[bold cyan]🤖 AI ASSISTANT SESSION[/bold cyan]",
            style="bold blue"
        ))
        
        # Session state
        session = {
            'history': [],  # List of {'role': 'user'|'assistant'|'system', 'content': str}
            'manual_context': [],  # List of user-supplied context strings
            'analysis_md': None,   # Loaded analysis markdown content
            'last_ai_response': None
        }
        
        # Load transcript context
        transcript_context = self._prepare_ai_context()
        # Optionally load previous analysis file
        def load_analysis_file():
            path = Prompt.ask("Enter path to previous analysis .md file (or leave blank to skip)", default="").strip()
            if path:
                try:
                    with open(path, 'r', encoding='utf-8') as f:
                        session['analysis_md'] = f.read()
                    self.console.print(f"[green]Loaded analysis file: {path}[/green]")
                except Exception as e:
                    self.console.print(f"[red]Failed to load analysis file: {e}[/red]")
        # Initial prompt
        load_analysis_file()
        # Manual context add helper
        def add_manual_context():
            ctx = Prompt.ask("Enter additional context/instructions to inject (or leave blank to cancel)", default="").strip()
            if ctx:
                session['manual_context'].append(ctx)
                self.console.print("[green]Manual context added for next AI call.[/green]")
        # Compose system prompt
        def build_system_prompt():
            sys_parts = []
            if self.ai_overrides:
                sys_parts.append(f"[OVERRIDES]\n{self.ai_overrides}")
            sys_parts.append(f"[TRANSCRIPT CONTEXT]\n{transcript_context}")
            if session['analysis_md']:
                sys_parts.append(f"[PREVIOUS ANALYSIS]\n{session['analysis_md']}")
            if session['manual_context']:
                sys_parts.append(f"[USER CONTEXT]\n" + "\n".join(session['manual_context']))
            return "\n\n".join(sys_parts)
        # Main assistant loop
        while True:
            # If no history, use default instructions as first user prompt
            if not session['history']:
                user_prompt = self.ai_default_instructions or "Enter your analysis prompt:"
            else:
                user_prompt = Prompt.ask("\n[cyan]Enter follow-up prompt, or leave blank to repeat last, or type 'menu' for options[/cyan]", default="").strip()
                if user_prompt.lower() == 'menu':
                    self.console.print("""
[bold]Assistant Session Menu:[/bold]
[1] Refine with new prompt
[2] Add manual context/instructions
[3] Load previous analysis file
[4] Export last AI response
[5] Exit assistant session
""")
                    menu_choice = Prompt.ask("Choose option (1-5)", default="1")
                    if menu_choice == "2":
                        add_manual_context()
                        continue
                    elif menu_choice == "3":
                        load_analysis_file()
                        continue
                    elif menu_choice == "4":
                        if session['last_ai_response']:
                            self._export_ai_result(session['last_ai_response'])
                        else:
                            self.console.print("[yellow]No AI response to export yet.[/yellow]")
                        continue
                    elif menu_choice == "5":
                        self.console.print("[yellow]Exiting assistant session.[/yellow]")
                        break
                    # else fall through to prompt
                    user_prompt = Prompt.ask("Enter your prompt:", default="").strip()
            if not user_prompt and session['history']:
                # Repeat last user prompt
                user_prompt = session['history'][-1]['content']
            elif not user_prompt:
                user_prompt = self.ai_default_instructions or "Enter your analysis prompt:"
            # Build message history
            messages = []
            # System prompt
            system_prompt = build_system_prompt()
            messages.append({"role": "system", "content": system_prompt + "\n\nFollow the user's instructions exactly. Exclude all chatfluff, meta-messaging, or references to being an AI or chat assistant. Only output the analysis and requested report content."})
            # Add all previous user/assistant turns
            for msg in session['history']:
                messages.append(msg)
            # Add current user prompt
            messages.append({"role": "user", "content": user_prompt})
            # Call OpenAI
            ai_response = None
            error_details = None
            with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}"), console=self.console) as progress:
                task = progress.add_task("🤖 Processing with AI...", total=100)
                if self.client is None:
                    self.console.print("[bold red]OpenAI client is not initialized. Cannot process AI queries.[/bold red]")
                    self.logger.error("Attempted AI query but OpenAI client is not initialized.")
                    input("\nPress Enter to continue...")
                    break
                try:
                    progress.update(task, description="Calling OpenAI", completed=10)
                    response = self.client.chat_completion(
                        messages=messages,
                        max_tokens=2000,
                        temperature=0.3
                    )
                    progress.update(task, description="Received AI response", completed=80)
                    ai_response = response.choices[0].message.content if response and response.choices else None
                    if not ai_response:
                        raise RuntimeError("No response from AI model.")
                except Exception as e:
                    error_details = traceback.format_exc()
                    self.console.print(f"❌ [red]Error processing query: {str(e)}[/red]")
                    self.console.print(f"[dim]{error_details}[/dim]")
                finally:
                    progress.update(task, completed=100)
            if ai_response:
                self.console.print(Panel(
                    ai_response,
                    title="🤖 AI Response",
                    border_style="green",
                    padding=(1, 2)
                ))
                session['last_ai_response'] = ai_response
                # Add to history
                session['history'].append({"role": "user", "content": user_prompt})
                session['history'].append({"role": "assistant", "content": ai_response})
                # After response, prompt user for next action
                self.console.print("""
[bold]What would you like to do next?[/bold]
[1] Accept/keep this result
[2] Refine with a follow-up prompt
[3] Add manual context/instructions
[4] Export this result
[5] Exit assistant session
""")
                next_action = Prompt.ask("Choose option (1-5)", default="1")
                if next_action == "2":
                    continue  # Loop for follow-up
                elif next_action == "3":
                    add_manual_context()
                    continue
                elif next_action == "4":
                    self._export_ai_result(ai_response)
                    continue
                elif next_action == "5":
                    self.console.print("[yellow]Exiting assistant session.[/yellow]")
                    break
                # else, accept/keep and exit
                break
            else:
                self.console.print("[yellow]No AI response. Try again or exit.")
                next_action = Prompt.ask("Try again? (y/n)", default="y")
                if next_action.lower().startswith('y'):
                    continue
                else:
                    break
        input("\nPress Enter to continue...")

    def export_results(self):
        """Export analysis results to a file (stub for menu compatibility)."""
        self.console.print("[yellow]Export functionality not yet implemented.[/yellow]")
        input("Press Enter to continue...")

    def _export_ai_result(self, ai_response):
        """Helper to export AI result to markdown file."""
        now = datetime.now().strftime('%y%m%d%H%M%S')
        default_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ai-analysis')
        os.makedirs(default_dir, exist_ok=True)
        default_filename = f"{now}-ai_analysis.md"
        default_path = os.path.join(default_dir, default_filename)
        self.console.print(f"\n[bold]Exporting AI analysis result...[/bold]")
        custom_path = Prompt.ask(
            f"Enter export path/filename for markdown (leave blank for default: {default_path})",
            default=""
        ).strip()
        export_path = custom_path if custom_path else default_path
        export_dir = os.path.dirname(export_path)
        os.makedirs(export_dir, exist_ok=True)
        with open(export_path, 'w', encoding='utf-8') as f:
            f.write(ai_response)
        self.console.print(f"✅ [green]AI analysis exported to: {export_path}[/green]")

    def run(self):
        """Main application loop."""
        self.show_welcome()
        # Prompt for transcript path
        transcript_path = Prompt.ask("Enter path to transcript JSON", default="parsed_transcript.json")
        if not self.load_transcript(transcript_path):
            return
        self.console.print("✅ [green]Analysis complete! Ready for queries.[/green]\n")
        while True:
            self.show_main_menu()
            
            choice = Prompt.ask("", default="9")
            
            if choice == "1":
                self.show_analysis_overview()
                input("\nPress Enter to continue...")
            elif choice == "2":
                self.browse_topics()
            elif choice == "3":
                self.show_speaker_insights()
            elif choice == "4":
                self.show_sentiment_analysis()
            elif choice == "5":
                self.show_diarization_analysis()
            elif choice == "6":
                self.search_and_query()
            elif choice == "7":
                self.ai_assistant_session()
            elif choice == "8":
                self.export_results()
            elif choice == "9":
                self.console.print("👋 [yellow]Thank you for using Transcript Analyzer![/yellow]")
                break
            else:
                self.console.print("❌ [red]Invalid choice. Please try again.[/red]")
                input("Press Enter to continue...")

    def search_and_query(self):
        """Basic search functionality."""
        self.console.clear()
        self.console.print(Panel(
            "[bold cyan]🔍 SEARCH & QUERY[/bold cyan]",
            style="bold blue"
        ))
        
        search_term = Prompt.ask("\n[cyan]Enter search term[/cyan]")
        
        if not search_term:
            return
        
        # Search through topics
        matching_topics = []
        for topic in self.topics:
            if (search_term.lower() in topic.title.lower() or 
                any(search_term.lower() in point.lower() for point in topic.key_points) or
                any(search_term.lower() in tag.lower() for tag in topic.tags)):
                matching_topics.append(topic)
        
        # Search through insights
        matching_insights = []
        for insight in self.insights:
            if search_term.lower() in insight.insight.lower():
                matching_insights.append(insight)
        
        # Display results
        if matching_topics:
            self.console.print(f"\n[green]Found {len(matching_topics)} matching topics:[/green]")
            for topic in matching_topics:
                self.console.print(f"• [cyan]{topic.title}[/cyan] ({topic.category})")
        
        if matching_insights:
            self.console.print(f"\n[green]Found {len(matching_insights)} matching insights:[/green]")
            for insight in matching_insights:
                self.console.print(f"• [cyan]{insight.speaker}:[/cyan] {insight.insight}")
        
        if not matching_topics and not matching_insights:
            self.console.print(f"❌ [red]No results found for '{search_term}'[/red]")
        
        input("\nPress Enter to continue...")

    def _prepare_ai_context(self):
        """Prepare a summary of the loaded transcript for AI context injection."""
        if not self.extractor or not hasattr(self.extractor, 'transcript_data') or not self.extractor.transcript_data:
            return "No transcript loaded."
        transcript_data = self.extractor.transcript_data
        meeting_info = transcript_data.get('meeting_info', {})
        summary_lines = []
        summary_lines.append(f"Meeting Date: {meeting_info.get('date', 'N/A')}")
        summary_lines.append(f"Participants: {', '.join(meeting_info.get('participants', []) or [])}")
        summary_lines.append(f"Total Messages: {meeting_info.get('total_messages', 'N/A')}")
        summary_lines.append(f"Estimated Duration: {meeting_info.get('duration_estimate', 'N/A')} minutes")
        summary_lines.append(f"\nTopics Discussed ({len(self.topics)}):")
        for topic in self.topics[:8]:
            summary_lines.append(f"- {topic.title} [{topic.category}] ({topic.duration_minutes:.1f} min)")
        if len(self.topics) > 8:
            summary_lines.append(f"...and {len(self.topics) - 8} more topics.")
        summary_lines.append(f"\nSpeakers: {', '.join(sorted(set(i.speaker for i in self.insights)))}")
        return '\n'.join(summary_lines)

if __name__ == "__main__":
    app = TranscriptAnalyzerTUI()
    app.run()
