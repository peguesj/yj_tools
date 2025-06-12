# TranscriptAnalysis (`@yj/tran`)

| Version | Date       | Author                              | Notes                |
|---------|------------|-------------------------------------|----------------------|
| 1.0.0   | 2025-06-12 | Jeremiah Pegues <jeremiah@pegues.io> | Initial package refactor |

---

## Overview

**TranscriptAnalysis** (`@yj/tran`) is a modular, best-practice Python package for advanced transcript analysis, including:
- Topic extraction & classification
- Speaker insights
- Sentiment analysis
- Diarization & speaking pattern analysis
- Interactive TUI for querying and reporting
- OpenAI/Azure OpenAI Assistants API integration (RAG, batch, and streaming)

All logic is organized for maintainability, extensibility, and cost-effective cloud AI usage.

---

## Installation

```sh
# From the root of your project:
pip install .
# Or, for editable development:
pip install -e .
```

This will install the `@yj/tran` package and add the `yj_tran_*` commands to your PATH (see below).

---

## Usage

### Command-line/TUI

```sh
yj_tran_tui  # Launches the interactive transcript analysis TUI
```

### Module Import

```python
from tran import TranscriptInsightExtractor, OpenAIClient
# ... use as shown in the codebase ...
```

---

## Directory Structure

```
tran/
    __init__.py
    extract_insights_clean.py
    openai_client.py
    transcript_analyzer_tui.py
    parse_transcript.py
    ai-analysis_default_instructions
    ai-analysis_overrides
    # ...other resource/data files as needed...
```

---

## Best Practices Commentary

- All OpenAI/Azure API calls are batched and use Assistants API for cost efficiency.
- Environment variables and `.env` are supported for all credentials/config.
- The TUI and CLI never make per-message or per-topic API calls; all analysis is performed in a single batch.
- All modules are type-annotated and documented inline.
- The package is fully modular and ready for extension.

---

## Version Control Table

| Version | Date       | Author                              | Notes                |
|---------|------------|-------------------------------------|----------------------|
| 1.0.0   | 2025-06-12 | Jeremiah Pegues <jeremiah@pegues.io> | Initial package refactor |

---

## Changelog

### 1.0.0 (2025-06-12)
- Initial refactor as `@yj/tran` package
- All analysis logic moved to `tran/`
- Added TUI, CLI, and batch analysis support
- Best-practice documentation and commentary throughout
