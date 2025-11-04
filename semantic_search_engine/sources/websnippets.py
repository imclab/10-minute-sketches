from __future__ import annotations

from typing import Iterable, List

from ..data import Hyperedge, Node, Source


class WebSnippetSource(Source):
    """Sampled mini web corpus representing internet knowledge."""

    def __init__(self) -> None:
        self.name = "web:snippets"
        self._snippets = [
            {
                "id": "web:wikipedia:deep_learning",
                "title": "Deep learning - Wikipedia",
                "summary": "Overview article describing deep neural networks and training techniques.",
                "url": "https://en.wikipedia.org/wiki/Deep_learning",
                "tags": ["wikipedia", "deep learning", "overview"],
            },
            {
                "id": "web:blog:ml_system_design",
                "title": "Building Reliable ML Systems",
                "summary": "Blog post on architecting end-to-end machine learning systems for production.",
                "url": "https://example.com/blog/ml-reliability",
                "tags": ["mlops", "architecture", "reliability"],
            },
            {
                "id": "web:spec:openapi",
                "title": "OpenAPI Specification",
                "summary": "Defines a standard, language-agnostic interface to REST APIs.",
                "url": "https://spec.openapis.org/oas/latest.html",
                "tags": ["api", "specification", "standards"],
            },
        ]

    def nodes(self) -> Iterable[Node]:
        nodes: List[Node] = []
        for snippet in self._snippets:
            nodes.append(
                Node(
                    id=snippet["id"],
                    label=snippet["title"],
                    kind="web",
                    metadata={
                        "description": snippet["summary"],
                        "url": snippet["url"],
                        "tags": snippet["tags"],
                    },
                )
            )
        return nodes

    def hyperedges(self) -> Iterable[Hyperedge]:
        edges: List[Hyperedge] = []
        for snippet in self._snippets:
            edges.append(
                Hyperedge(
                    id=f"web:tag:{snippet['id']}",
                    relation="tagged",
                    node_ids=(snippet["id"],),
                    metadata={"tags": snippet["tags"]},
                )
            )
        return edges
