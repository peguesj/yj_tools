#!/usr/bin/env python3
"""
Advanced Transcript Insight Extraction System
Extracts comprehensive insights from meeting transcripts with hierarchical analysis.
"""

import json
import re
import os
from datetime import datetime
from typing import Dict, List, Any, Tuple, Optional
from dataclasses import dataclass, asdict
from collections import defaultdict, Counter
from openai_client import OpenAIClient
from textblob import TextBlob

@dataclass
class TopicDiscussion:
    id: str
    title: str
    tags: List[str]
    category: str  # personal, professional, technical, strategic
    subcategory: str
    start_time: str
    end_time: str
    duration_minutes: float
    message_count: int
    speakers: List[str]
    key_points: List[str]
    decisions: List[str]
    action_items: List[str]
    context_score: float  # relevance to overall conversation
    
@dataclass 
class SpeakerInsight:
    speaker: str
    topic_id: str
    insight: str
    tags: List[str]
    confidence_score: float
    supporting_evidence: List[str]
    sentiment: str
    expertise_level: str  # novice, intermediate, expert, authority
    engagement_level: str  # low, medium, high, dominant
    
@dataclass
class SentimentAnalysis:
    overall_sentiment: str
    confidence: float
    emotional_intensity: float
    speaker_sentiments: Dict[str, Dict[str, Any]]
    topic_sentiments: Dict[str, Dict[str, Any]]
    sentiment_timeline: List[Dict[str, Any]]

@dataclass
class Diarization:
    speaker: str
    speaking_percentage: float
    total_words: int
    average_message_length: float
    interruption_count: int
    question_count: int
    statement_count: int
    dominant_topics: List[str]
    communication_style: str
    technical_vocabulary_score: float
    
class TranscriptInsightExtractor:
    def __init__(self, transcript_file: str):
        self.client = OpenAIClient()
        with open(transcript_file, 'r') as f:
            self.transcript_data = json.load(f)
        
        self.conversations = self.transcript_data['conversation']
        self.participants = self.transcript_data['meeting_info']['participants']
        
        # Technical and business keywords for classification
        self.technical_keywords = {
            'ai_ml': ['ai', 'ml', 'machine learning', 'artificial intelligence', 'model', 'training', 'algorithm', 'neural network', 'gpt', 'claude', 'llm', 'prompt', 'inference'],
            'development': ['code', 'coding', 'programming', 'development', 'github', 'vercel', 'react', 'javascript', 'python', 'api', 'database', 'frontend', 'backend', 'microservices'],
            'security': ['security', 'compliance', 'encryption', 'authentication', 'authorization', 'vulnerabilities', 'threats', 'cybersecurity', 'siem', 'soc'],
            'business': ['client', 'customer', 'revenue', 'pricing', 'sales', 'marketing', 'business model', 'strategy', 'competitive', 'market'],
            'infrastructure': ['cloud', 'aws', 'azure', 'kubernetes', 'docker', 'infrastructure', 'deployment', 'scaling', 'architecture'],
            'automation': ['automation', 'workflow', 'process', 'efficiency', 'optimization', 'integration', 'pipeline']
        }
        
        self.business_keywords = {
            'strategy': ['strategy', 'strategic', 'vision', 'roadmap', 'planning', 'objectives', 'goals'],
            'operations': ['operations', 'process', 'workflow', 'efficiency', 'optimization', 'management'],
            'finance': ['cost', 'pricing', 'revenue', 'budget', 'investment', 'roi', 'financial'],
            'sales': ['sales', 'selling', 'prospect', 'lead', 'conversion', 'pipeline', 'funnel'],
            'product': ['product', 'feature', 'development', 'iteration', 'feedback', 'user experience']
        }

    def extract_topics(self) -> List[TopicDiscussion]:
        """Extract and classify topics from the conversation using keyword analysis only (no AI calls)."""
        topics = []
        current_topic = None
        topic_buffer = []
        
        # Use sliding window approach to identify topic boundaries
        for i, msg in enumerate(self.conversations):
            # Analyze message for topic indicators
            message_topics = self._classify_message_topics(msg['message'])
            
            # Check for topic transitions
            if self._is_topic_transition(topic_buffer, msg, message_topics):
                if current_topic and topic_buffer:
                    # Finalize current topic
                    topic = self._finalize_topic(current_topic, topic_buffer)
                    if topic:
                        topics.append(topic)
                
                # Start new topic
                current_topic = self._start_new_topic(message_topics, msg)
                topic_buffer = [msg]
            else:
                topic_buffer.append(msg)
                if current_topic:
                    current_topic = self._update_topic(current_topic, message_topics)
        
        # Handle final topic
        if current_topic and topic_buffer:
            topic = self._finalize_topic(current_topic, topic_buffer)
            if topic:
                topics.append(topic)
        
        return topics

    def _classify_message_topics(self, message: str) -> Dict[str, float]:
        """Classify message into topic categories with confidence scores."""
        message_lower = message.lower()
        scores = {}
        
        # Technical classification
        for category, keywords in self.technical_keywords.items():
            score = sum(1 for keyword in keywords if keyword in message_lower)
            if score > 0:
                scores[f"tech_{category}"] = score / len(keywords)
        
        # Business classification
        for category, keywords in self.business_keywords.items():
            score = sum(1 for keyword in keywords if keyword in message_lower)
            if score > 0:
                scores[f"business_{category}"] = score / len(keywords)
        
        # Personal vs Professional classification
        personal_indicators = ['personal', 'family', 'life', 'feeling', 'tired', 'weekend']
        professional_indicators = ['project', 'client', 'work', 'business', 'meeting', 'deadline']
        
        personal_score = sum(1 for indicator in personal_indicators if indicator in message_lower)
        professional_score = sum(1 for indicator in professional_indicators if indicator in message_lower)
        
        if personal_score > professional_score:
            scores['personal'] = personal_score / len(personal_indicators)
        else:
            scores['professional'] = professional_score / len(professional_indicators)
        
        return scores

    def _is_topic_transition(self, topic_buffer: List[Dict], current_msg: Dict, current_topics: Dict[str, float]) -> bool:
        """Determine if current message indicates a topic transition."""
        if not topic_buffer:
            return True
        
        # Check for explicit transition phrases
        transition_phrases = [
            "moving on", "next topic", "switching to", "let's talk about",
            "on another note", "changing subjects", "speaking of"
        ]
        
        msg_lower = current_msg['message'].lower()
        if any(phrase in msg_lower for phrase in transition_phrases):
            return True
        
        # Check for significant topic score changes
        if len(topic_buffer) >= 3:
            recent_topics = [self._classify_message_topics(msg['message']) for msg in topic_buffer[-3:]]
            avg_recent_scores = self._average_topic_scores(recent_topics)
            
            # Compare current topics with recent average
            for topic, score in current_topics.items():
                if topic not in avg_recent_scores or abs(score - avg_recent_scores[topic]) > 0.3:
                    return True
        
        return False

    def _average_topic_scores(self, topic_lists: List[Dict[str, float]]) -> Dict[str, float]:
        """Calculate average topic scores across multiple classifications."""
        all_topics = set()
        for topics in topic_lists:
            all_topics.update(topics.keys())
        
        averages = {}
        for topic in all_topics:
            scores = [topics.get(topic, 0) for topics in topic_lists]
            averages[topic] = sum(scores) / len(scores)
        
        return averages

    def _start_new_topic(self, message_topics: Dict[str, float], msg: Dict) -> Dict[str, Any]:
        """Initialize a new topic discussion."""
        # Determine primary topic
        if not message_topics:
            primary_topic = "general_discussion"
            category = "general"
        else:
            primary_topic = max(message_topics.items(), key=lambda x: x[1])[0]
            category = "technical" if primary_topic.startswith("tech_") else "business"
        
        return {
            'primary_topic': primary_topic,
            'category': category,
            'start_time': msg['timestamp'],
            'speakers': {msg['speaker']},
            'topics_discussed': message_topics,
            'messages': []
        }

    def _update_topic(self, current_topic: Dict[str, Any], message_topics: Dict[str, float]) -> Dict[str, Any]:
        """Update current topic with new message information."""
        # Merge topic scores
        for topic, score in message_topics.items():
            if topic in current_topic['topics_discussed']:
                current_topic['topics_discussed'][topic] = max(
                    current_topic['topics_discussed'][topic], score
                )
            else:
                current_topic['topics_discussed'][topic] = score
        
        return current_topic

    def _finalize_topic(self, topic_data: Dict[str, Any], messages: List[Dict]) -> Optional[TopicDiscussion]:
        """Convert topic data to TopicDiscussion object."""
        if not messages:
            return None
        
        # Generate topic title using AI
        topic_title = self._generate_topic_title(messages)
        
        # Calculate duration
        start_time = messages[0]['timestamp']
        end_time = messages[-1]['timestamp']
        duration = self._calculate_duration(start_time, end_time)
        
        # Extract key points and decisions
        key_points, decisions, action_items = self._extract_key_content(messages)
        
        # Generate tags
        tags = self._generate_tags(topic_data['topics_discussed'], messages)
        
        return TopicDiscussion(
            id=f"topic_{hash(topic_title)}",
            title=topic_title,
            tags=tags,
            category=topic_data['category'],
            subcategory=topic_data['primary_topic'],
            start_time=start_time,
            end_time=end_time,
            duration_minutes=duration,
            message_count=len(messages),
            speakers=list(topic_data['speakers']),
            key_points=key_points,
            decisions=decisions,
            action_items=action_items,
            context_score=self._calculate_context_score(messages)
        )

    def _generate_topic_title(self, messages: List[dict], use_ai=True) -> str:
        """Always use keyword-based title generation (no AI calls)."""
        return self._generate_keyword_title(messages)

    def _generate_keyword_title(self, messages: List[Dict]) -> str:
        """Generate title based on most frequent meaningful words."""
        text = " ".join([msg['message'] for msg in messages])
        words = re.findall(r'\b[a-zA-Z]{4,}\b', text.lower())
        
        # Filter out common words
        stop_words = {'that', 'this', 'with', 'have', 'will', 'from', 'they', 'been', 'were', 'said', 'each', 'which', 'their', 'time', 'like', 'just', 'know', 'think', 'want', 'need', 'make', 'come', 'going', 'really', 'would', 'could', 'should'}
        meaningful_words = [word for word in words if word not in stop_words]
        
        word_freq = Counter(meaningful_words)
        top_words = [word for word, _ in word_freq.most_common(3)]
        
        return " ".join(top_words).title() if top_words else "General Discussion"

    def _calculate_duration(self, start_time: str, end_time: str) -> float:
        """Calculate duration between timestamps in minutes."""
        try:
            start = datetime.strptime(start_time, "%Y-%m-%d %I:%M %p")
            end = datetime.strptime(end_time, "%Y-%m-%d %I:%M %p")
            return (end - start).total_seconds() / 60
        except:
            return 0.0

    def _extract_key_content(self, messages: List[Dict]) -> Tuple[List[str], List[str], List[str]]:
        """Extract key points, decisions, and action items from messages."""
        key_points = []
        decisions = []
        action_items = []
        
        decision_indicators = ['decided', 'agreed', 'conclusion', 'final', 'settled']
        action_indicators = ['will', 'should', 'need to', 'going to', 'plan to', 'next step']
        
        for msg in messages:
            content = msg['message'].lower()
            
            # Check for decisions
            if any(indicator in content for indicator in decision_indicators):
                decisions.append(msg['message'][:200])
            
            # Check for action items
            if any(indicator in content for indicator in action_indicators):
                action_items.append(msg['message'][:200])
            
            # Important statements (heuristic)
            if len(msg['message']) > 100 and ('important' in content or 'key' in content):
                key_points.append(msg['message'][:200])
        
        return key_points[:5], decisions[:3], action_items[:5]

    def _generate_tags(self, topic_scores: Dict[str, float], messages: List[Dict]) -> List[str]:
        """Generate relevant tags for the topic."""
        tags = []
        
        # Add topic-based tags
        for topic, score in topic_scores.items():
            if score > 0.1:  # Threshold for relevance
                tags.append(topic.replace('_', '-'))
        
        # Add behavioral tags based on message content
        all_text = " ".join([msg['message'] for msg in messages]).lower()
        
        if any(word in all_text for word in ['question', 'how', 'what', 'why', 'when']):
            tags.append('questioning')
        if any(word in all_text for word in ['suggest', 'recommend', 'propose']):
            tags.append('advisory')
        if any(word in all_text for word in ['concern', 'worry', 'risk']):
            tags.append('cautious')
        if any(word in all_text for word in ['excited', 'great', 'awesome', 'love']):
            tags.append('enthusiastic')
        
        return list(set(tags))

    def _calculate_context_score(self, messages: List[Dict]) -> float:
        """Calculate the relevance/importance score of the topic."""
        # Score based on message length, participant engagement, and keyword density
        total_length = sum(len(msg['message']) for msg in messages)
        unique_speakers = len(set(msg['speaker'] for msg in messages))
        
        # Normalize scores
        length_score = min(total_length / 1000, 1.0)  # Cap at 1000 characters
        speaker_score = unique_speakers / len(self.participants)
        
        return (length_score + speaker_score) / 2

    def extract_speaker_insights(self, topics: List[TopicDiscussion]) -> List[SpeakerInsight]:
        """Extract insights about each speaker's contributions and perspectives."""
        insights = []
        
        # Group messages by speaker and topic
        for topic in topics:
            topic_messages = [msg for msg in self.conversations 
                            if topic.start_time <= msg['timestamp'] <= topic.end_time]
            
            speaker_contributions = {}
            for msg in topic_messages:
                speaker = msg['speaker']
                if speaker not in speaker_contributions:
                    speaker_contributions[speaker] = []
                speaker_contributions[speaker].append(msg)
            
            # Generate insights for each speaker in this topic
            for speaker, messages in speaker_contributions.items():
                if len(messages) >= 2:  # Minimum threshold for insight generation
                    insight = self._generate_speaker_insight(speaker, messages, topic)
                    if insight:
                        insights.append(insight)
        
        return insights

    def _generate_speaker_insight(self, speaker: str, messages: List[Dict], topic: TopicDiscussion) -> Optional[SpeakerInsight]:
        """Generate a specific insight about a speaker's contribution to a topic."""
        combined_text = " ".join([msg['message'] for msg in messages])
        
        # Use AI to generate insight
        try:
            insight_text = self._generate_ai_insight(speaker, combined_text, topic.title)
        except:
            insight_text = self._generate_heuristic_insight(speaker, messages, topic)
        
        # Analyze sentiment of speaker's contributions
        blob = TextBlob(combined_text)
        sentiment = self._classify_sentiment(blob.sentiment.polarity)
        
        # Determine expertise and engagement levels
        expertise_level = self._assess_expertise_level(combined_text)
        engagement_level = self._assess_engagement_level(messages, topic)
        
        # Generate tags
        tags = self._generate_insight_tags(combined_text, messages)
        
        # Calculate confidence
        confidence = self._calculate_insight_confidence(messages, topic)
        
        # Supporting evidence
        evidence = [msg['message'][:150] + "..." for msg in messages[:3]]
        
        return SpeakerInsight(
            speaker=speaker,
            topic_id=topic.id,
            insight=insight_text,
            tags=tags,
            confidence_score=confidence,
            supporting_evidence=evidence,
            sentiment=sentiment,
            expertise_level=expertise_level,
            engagement_level=engagement_level
        )

    def _generate_ai_insight(self, speaker: str, text: str, topic_title: str) -> str:
        """Generate insight using OpenAI chat completion (via OpenAIClient)."""
        response = self.client.chat_completion(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "Generate a concise insight (1-2 sentences) about a speaker's contribution to a topic discussion. Focus on their perspective, expertise, or unique viewpoint."},
                {"role": "user", "content": f"Speaker: {speaker}\nTopic: {topic_title}\nContribution: {text[:500]}"}
            ],
            max_tokens=100,
            temperature=0.7
        )
        return response.choices[0].message['content'].strip() if response.choices else ""

    def _generate_heuristic_insight(self, speaker: str, messages: List[Dict], topic: TopicDiscussion) -> str:
        """Generate insight using heuristic analysis as fallback."""
        message_count = len(messages)
        avg_length = sum(len(msg['message']) for msg in messages) / message_count
        
        if avg_length > 100:
            return f"{speaker} provided detailed explanations and deep insights on {topic.title}"
        elif message_count > 5:
            return f"{speaker} was highly engaged in the discussion about {topic.title}"
        else:
            return f"{speaker} contributed to the conversation about {topic.title}"

    def _assess_expertise_level(self, text: str) -> str:
        """Assess speaker's expertise level based on their language."""
        text_lower = text.lower()
        
        # Count technical terms
        technical_count = 0
        for keywords in self.technical_keywords.values():
            technical_count += sum(1 for keyword in keywords if keyword in text_lower)
        
        word_count = len(text.split())
        if word_count == 0:
            return "novice"
        
        technical_ratio = technical_count / word_count
        
        if technical_ratio > 0.1:
            return "expert"
        elif technical_ratio > 0.05:
            return "intermediate"
        else:
            return "novice"

    def _assess_engagement_level(self, messages: List[Dict], topic: TopicDiscussion) -> str:
        """Assess speaker's engagement level in the topic."""
        message_count = len(messages)
        total_topic_messages = topic.message_count
        
        participation_ratio = message_count / total_topic_messages if total_topic_messages > 0 else 0
        
        if participation_ratio > 0.6:
            return "dominant"
        elif participation_ratio > 0.3:
            return "high"
        elif participation_ratio > 0.1:
            return "medium"
        else:
            return "low"

    def _generate_insight_tags(self, text: str, messages: List[Dict]) -> List[str]:
        """Generate tags for the insight."""
        tags = []
        text_lower = text.lower()
        
        # Content-based tags
        if any(word in text_lower for word in ['question', 'how', 'what', 'why', 'when']):
            tags.append('questioning')
        if any(word in text_lower for word in ['suggest', 'recommend', 'propose']):
            tags.append('advisory')
        if any(word in text_lower for word in ['concern', 'worry', 'risk']):
            tags.append('cautious')
        if any(word in text_lower for word in ['excited', 'great', 'awesome', 'love']):
            tags.append('enthusiastic')
        
        return list(set(tags))

    def _calculate_insight_confidence(self, messages: List[Dict], topic: TopicDiscussion) -> float:
        """Calculate confidence score for the insight."""
        message_count = len(messages)
        total_length = sum(len(msg['message']) for msg in messages)
        
        # Higher confidence for more substantial contributions
        count_score = min(message_count / 5, 1.0)
        length_score = min(total_length / 500, 1.0)
        
        return (count_score + length_score) / 2

    def _get_sentiment_scores(self, blob):
        """Safely extract polarity and subjectivity from a TextBlob blob."""
        try:
            sentiment = blob.sentiment
            polarity = getattr(sentiment, 'polarity', 0.0)
            subjectivity = getattr(sentiment, 'subjectivity', 0.0)
        except Exception:
            polarity = 0.0
            subjectivity = 0.0
        return polarity, subjectivity

    def _classify_sentiment(self, polarity: float) -> str:
        """
        Classify sentiment as 'positive', 'neutral', or 'negative' based on polarity.
        Best practice: Use clear, explainable thresholds and document them. See OpenAI and TextBlob docs for guidance.
        """
        if polarity > 0.15:
            return "positive"
        elif polarity < -0.15:
            return "negative"
        else:
            return "neutral"

    def _generate_sentiment_tags(self, sentiment, text: str) -> list:
        """
        Generate sentiment tags based on polarity, subjectivity, and text cues.
        Best practice: Use interpretable tags and combine statistical and heuristic cues. See OpenAI docs on explainability.
        """
        tags = []
        polarity = getattr(sentiment, 'polarity', 0.0)
        subjectivity = getattr(sentiment, 'subjectivity', 0.0)
        if polarity > 0.15:
            tags.append("positive")
        elif polarity < -0.15:
            tags.append("negative")
        else:
            tags.append("neutral")
        if subjectivity > 0.5:
            tags.append("subjective")
        else:
            tags.append("objective")
        if abs(polarity) > 0.5:
            tags.append("intense")
        # Heuristic: look for emotional words
        text_lower = text.lower()
        if any(word in text_lower for word in ["excited", "love", "hate", "angry", "worried"]):
            tags.append("emotional")
        return list(set(tags))

    def _analyze_topic_diarization(self, topic_messages: list) -> dict:
        """
        Analyze speaker participation and engagement for a topic.
        Best practice: Provide interpretable, actionable metrics. See OpenAI docs on conversational analytics.
        """
        if not topic_messages:
            return {}
        speaker_counts = Counter(msg['speaker'] for msg in topic_messages)
        total = sum(speaker_counts.values())
        participation = {speaker: count / total for speaker, count in speaker_counts.items()}
        most_active_speaker = None
        if speaker_counts:
            most_active_speaker = max(list(speaker_counts.keys()), key=lambda k: speaker_counts[k])
        return {
            "speaker_participation": participation,
            "most_active_speaker": most_active_speaker,
            "unique_speakers": len(speaker_counts)
        }

    def analyze_sentiment(self, topics: List[TopicDiscussion]) -> SentimentAnalysis:
        """Perform comprehensive sentiment analysis."""
        all_messages = self.conversations
        all_text = " ".join([msg['message'] for msg in all_messages])
        overall_blob = TextBlob(all_text)
        overall_polarity, overall_subjectivity = self._get_sentiment_scores(overall_blob)
        overall_sentiment = self._classify_sentiment(overall_polarity)
        # Speaker-specific sentiment
        speaker_sentiments = {}
        for speaker in self.participants:
            speaker_messages = [msg for msg in all_messages if msg['speaker'] == speaker]
            speaker_text = " ".join([msg['message'] for msg in speaker_messages])
            speaker_blob = TextBlob(speaker_text)
            polarity, subjectivity = self._get_sentiment_scores(speaker_blob)
            speaker_sentiments[speaker] = {
                'overall_sentiment': self._classify_sentiment(polarity),
                'polarity': polarity,
                'subjectivity': subjectivity,
                'emotional_intensity': abs(polarity),
                'message_count': len(speaker_messages),
                'tags': self._generate_sentiment_tags(speaker_blob.sentiment, speaker_text)
            }
        # Topic-specific sentiment
        topic_sentiments = {}
        for topic in topics:
            topic_messages = [msg for msg in all_messages 
                            if topic.start_time <= msg['timestamp'] <= topic.end_time]
            topic_text = " ".join([msg['message'] for msg in topic_messages])
            topic_blob = TextBlob(topic_text)
            polarity, subjectivity = self._get_sentiment_scores(topic_blob)
            topic_sentiments[topic.id] = {
                'sentiment': self._classify_sentiment(polarity),
                'polarity': polarity,
                'subjectivity': subjectivity,
                'tags': self._generate_sentiment_tags(topic_blob.sentiment, topic_text),
                'diarization': self._analyze_topic_diarization(topic_messages)
            }
        # Sentiment timeline
        sentiment_timeline = self._create_sentiment_timeline(all_messages)
        return SentimentAnalysis(
            overall_sentiment=overall_sentiment,
            confidence=abs(overall_polarity),
            emotional_intensity=abs(overall_polarity),
            speaker_sentiments=speaker_sentiments,
            topic_sentiments=topic_sentiments,
            sentiment_timeline=sentiment_timeline
        )

    def _create_sentiment_timeline(self, messages: List[Dict]) -> List[Dict[str, Any]]:
        """Create a timeline of sentiment changes throughout the conversation."""
        timeline = []
        window_size = 10  # Analyze sentiment in chunks of 10 messages
        for i in range(0, len(messages), window_size):
            chunk = messages[i:i+window_size]
            chunk_text = " ".join([msg['message'] for msg in chunk])
            chunk_blob = TextBlob(chunk_text)
            polarity, subjectivity = self._get_sentiment_scores(chunk_blob)
            timeline.append({
                'start_message': i,
                'end_message': min(i + window_size - 1, len(messages) - 1),
                'timestamp': chunk[0]['timestamp'],
                'sentiment': self._classify_sentiment(polarity),
                'polarity': polarity,
                'subjectivity': subjectivity
            })
        return timeline

    def analyze_diarization(self) -> List[Diarization]:
        """Perform comprehensive diarization analysis."""
        diarization_results = []
        
        # Calculate total conversation statistics
        total_messages = len(self.conversations)
        total_words = sum(len(msg['message'].split()) for msg in self.conversations)
        
        for speaker in self.participants:
            speaker_messages = [msg for msg in self.conversations if msg['speaker'] == speaker]
            
            if not speaker_messages:
                continue
            
            # Basic statistics
            speaker_message_count = len(speaker_messages)
            speaker_words = sum(len(msg['message'].split()) for msg in speaker_messages)
            
            # Speaking patterns
            speaking_percentage = (speaker_message_count / total_messages) * 100
            average_message_length = speaker_words / speaker_message_count if speaker_message_count > 0 else 0
            
            # Count questions and interruptions
            question_count = sum(1 for msg in speaker_messages if '?' in msg['message'])
            
            # Estimate interruptions by looking at very short messages following longer ones
            interruption_count = 0
            for i, msg in enumerate(speaker_messages):
                if i > 0 and len(msg['message'].split()) < 3 and len(speaker_messages[i-1]['message'].split()) > 10:
                    interruption_count += 1
            
            statement_count = speaker_message_count - question_count
            
            # Analyze dominant topics (simplified)
            speaker_text = " ".join([msg['message'] for msg in speaker_messages])
            dominant_topics = self._extract_dominant_topics_for_speaker(speaker_text)
            
            # Communication style analysis
            communication_style = self._analyze_communication_style(speaker_messages)
            
            # Technical vocabulary score
            technical_score = self._calculate_technical_vocabulary_score(speaker_text)
            
            diarization_results.append(Diarization(
                speaker=speaker,
                speaking_percentage=speaking_percentage,
                total_words=speaker_words,
                average_message_length=average_message_length,
                interruption_count=interruption_count,
                question_count=question_count,
                statement_count=statement_count,
                dominant_topics=dominant_topics,
                communication_style=communication_style,
                technical_vocabulary_score=technical_score
            ))
        
        return diarization_results

    def _extract_dominant_topics_for_speaker(self, speaker_text: str) -> List[str]:
        """Extract dominant topics for a specific speaker."""
        text_lower = speaker_text.lower()
        topic_scores = {}
        
        # Score based on technical keywords
        for category, keywords in self.technical_keywords.items():
            score = sum(1 for keyword in keywords if keyword in text_lower)
            if score > 0:
                topic_scores[category] = score
        
        # Score based on business keywords
        for category, keywords in self.business_keywords.items():
            score = sum(1 for keyword in keywords if keyword in text_lower)
            if score > 0:
                topic_scores[category] = score
        
        # Return top 3 topics
        sorted_topics = sorted(topic_scores.items(), key=lambda x: x[1], reverse=True)
        return [topic for topic, score in sorted_topics[:3]]

    def _analyze_communication_style(self, messages: List[Dict]) -> str:
        """Analyze and classify communication style."""
        if not messages:
            return "unknown"
        
        total_text = " ".join([msg['message'] for msg in messages])
        avg_message_length = len(total_text.split()) / len(messages)
        question_ratio = sum(1 for msg in messages if '?' in msg['message']) / len(messages)
        
        # Classify based on patterns
        if avg_message_length > 50:
            if question_ratio > 0.3:
                return "detailed_inquisitive"
            else:
                return "detailed_explanatory"
        elif avg_message_length > 20:
            if question_ratio > 0.3:
                return "conversational_questioning"
            else:
                return "conversational_informative"
        else:
            if question_ratio > 0.3:
                return "brief_questioning"
            else:
                return "brief_direct"

    def _calculate_technical_vocabulary_score(self, text: str) -> float:
        """Calculate how technical the vocabulary is."""
        text_lower = text.lower()
        words = text_lower.split()
        
        if not words:
            return 0.0
        
        technical_word_count = 0
        all_technical_words = []
        
        # Collect all technical keywords
        for keywords in self.technical_keywords.values():
            all_technical_words.extend(keywords)
        
        # Count technical words
        for word in words:
            if word in all_technical_words:
                technical_word_count += 1
        
        return technical_word_count / len(words)

    def extract_comprehensive_insights(self) -> Dict[str, Any]:
        """Main method to extract all insights from the transcript."""
        # Extract topics
        topics = self.extract_topics()
        
        # Extract speaker insights
        speaker_insights = self.extract_speaker_insights(topics)
        
        # Perform sentiment analysis
        sentiment_analysis = self.analyze_sentiment(topics)
        
        # Perform diarization
        diarization = self.analyze_diarization()
        
        # Compile comprehensive insights
        insights = {
            'extraction_metadata': {
                'timestamp': datetime.now().isoformat(),
                'total_messages_analyzed': len(self.conversations),
                'participants': self.participants,
                'analysis_version': '1.0'
            },
            'topics_discussed': [asdict(topic) for topic in topics],
            'speaker_insights': [asdict(insight) for insight in speaker_insights],
            'sentiment_analysis': asdict(sentiment_analysis),
            'diarization': [asdict(d) for d in diarization],
            'summary_statistics': {
                'total_topics': len(topics),
                'total_insights': len(speaker_insights),
                'average_topic_duration': sum(t.duration_minutes for t in topics) / len(topics) if topics else 0,
                'most_active_speaker': max(diarization, key=lambda x: x.speaking_percentage).speaker if diarization else None,
                'dominant_categories': self._get_dominant_categories(topics),
                'key_themes': self._extract_key_themes(topics)
            }
        }
        
        return insights

    def _get_dominant_categories(self, topics: List[TopicDiscussion]) -> List[str]:
        """Get the most frequently discussed categories."""
        categories = [topic.category for topic in topics]
        category_counts = Counter(categories)
        return [cat for cat, count in category_counts.most_common(3)]

    def _extract_key_themes(self, topics: List[TopicDiscussion]) -> List[str]:
        """Extract overarching themes from all topics."""
        all_tags = []
        for topic in topics:
            all_tags.extend(topic.tags)
        
        tag_counts = Counter(all_tags)
        return [tag for tag, count in tag_counts.most_common(5)]

def main():
    """Main execution function."""
    if not os.path.exists('parsed_transcript.json'):
        print("Error: parsed_transcript.json not found. Please run parse_transcript.py first.")
        return
    
    print("Starting comprehensive insight extraction...")
    extractor = TranscriptInsightExtractor('parsed_transcript.json')
    
    insights = extractor.extract_comprehensive_insights()
    
    # Save insights to file
    output_file = 'transcript_insights.json'
    with open(output_file, 'w') as f:
        json.dump(insights, f, indent=2, default=str)
    
    print(f"\nInsights extracted successfully!")
    print(f"Output saved to: {output_file}")
    print(f"Total topics analyzed: {insights['summary_statistics']['total_topics']}")
    print(f"Total insights generated: {insights['summary_statistics']['total_insights']}")
    print(f"Most active speaker: {insights['summary_statistics']['most_active_speaker']}")
    print(f"Dominant categories: {', '.join(insights['summary_statistics']['dominant_categories'])}")
    print(f"Key themes: {', '.join(insights['summary_statistics']['key_themes'])}")

if __name__ == "__main__":
    main()
