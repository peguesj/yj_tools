from setuptools import setup, find_packages
import os
import setuptools
from setuptools.command.install import install
from pathlib import Path
import shutil

class PostInstallCommand(install):
    """
    Custom install command to symlink or copy required files into tran/ after install.
    This ensures all resources are available in the package directory for @yj/tran.
    """
    def run(self):
        install.run(self)
        ROOT = Path(__file__).parent.resolve()
        TRAN = ROOT / 'tran'
        TRAN.mkdir(exist_ok=True)
        REQUIRED = [
            'extract_insights_clean.py',
            'openai_client.py',
            'transcript_analyzer_tui.py',
            'parse_transcript.py',
            'ai-analysis_default_instructions',
            'ai-analysis_overrides',
        ]
        for fname in REQUIRED:
            src = ROOT / fname
            dst = TRAN / fname
            if src.exists():
                if dst.exists():
                    print(f"[SKIP] {dst} already exists.")
                else:
                    try:
                        os.symlink(src, dst)
                        print(f"[SYMLINK] {src} -> {dst}")
                    except Exception as e:
                        shutil.copy(str(src), str(dst))
                        print(f"[COPY] {src} -> {dst} (symlink failed: {e})")

setup(
    name='yj-tran',
    version='1.0.0',
    description='TranscriptAnalysis - Advanced transcript analysis and TUI',
    long_description=open('README.md').read() if os.path.exists('README.md') else '',
    long_description_content_type='text/markdown',
    author='Jeremiah Pegues',
    author_email='jeremiah@pegues.io',
    packages=find_packages(include=['tran', 'tran.*']),
    include_package_data=True,
    install_requires=[
        'openai',
        'textblob',
        'python-dotenv',
        'rich',
    ],
    entry_points={
        'console_scripts': [
            'yj_tran_tui=tran:tui',
            'yj_tran_parse=tran:parse',
        ],
    },
    package_data={
        'tran': [
            'ai-analysis_default_instructions',
            'ai-analysis_overrides',
        ],
    },
    python_requires='>=3.8',
    classifiers=[
        'Programming Language :: Python :: 3',
        'Operating System :: OS Independent',
    ],
    cmdclass={
        'install': PostInstallCommand,
    },
)
