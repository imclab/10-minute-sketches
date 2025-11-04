"""Knowledge sources feeding the semantic search engine."""

from .filesystem import FileSystemSource
from .science import SamplePapersSource
from .websnippets import WebSnippetSource

__all__ = [
    "FileSystemSource",
    "SamplePapersSource",
    "WebSnippetSource",
]
