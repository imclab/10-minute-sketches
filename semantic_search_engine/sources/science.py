from __future__ import annotations

from typing import Iterable, List

from ..data import Hyperedge, Node, Source


class SamplePapersSource(Source):
    """Curated mini corpus of scientific papers for demonstration."""

    def __init__(self) -> None:
        self.name = "science:sample"
        self._papers = [
            {
                "id": "paper:attention_is_all_you_need",
                "title": "Attention Is All You Need",
                "year": 2017,
                "authors": ["Vaswani", "Shazeer", "Parmar"],
                "abstract": "Transformer architecture using self-attention for machine translation.",
                "topics": ["deep learning", "transformers", "nlp"],
            },
            {
                "id": "paper:imagenet_classification",
                "title": "ImageNet Classification with Deep Convolutional Neural Networks",
                "year": 2012,
                "authors": ["Krizhevsky", "Sutskever", "Hinton"],
                "abstract": "Introduces AlexNet and demonstrates breakthrough performance on ImageNet.",
                "topics": ["computer vision", "cnn", "deep learning"],
            },
            {
                "id": "paper:alphafold",
                "title": "Highly accurate protein structure prediction with AlphaFold",
                "year": 2021,
                "authors": ["Jumper", "Evans", "Hassabis"],
                "abstract": "AlphaFold models protein folding with transformer-like networks and evolutionary data.",
                "topics": ["biology", "deep learning", "protein folding"],
            },
        ]

    def nodes(self) -> Iterable[Node]:
        nodes: List[Node] = []
        for paper in self._papers:
            nodes.append(
                Node(
                    id=paper["id"],
                    label=paper["title"],
                    kind="paper",
                    metadata={
                        "description": paper["abstract"],
                        "year": paper["year"],
                        "tags": paper["topics"],
                        "authors": paper["authors"],
                    },
                )
            )
        return nodes

    def hyperedges(self) -> Iterable[Hyperedge]:
        edges: List[Hyperedge] = []
        # Connect papers sharing topics with thematic hyperedges.
        topic_to_papers: dict[str, List[str]] = {}
        for paper in self._papers:
            for topic in paper["topics"]:
                topic_to_papers.setdefault(topic, []).append(paper["id"])
        for topic, paper_ids in topic_to_papers.items():
            if len(paper_ids) > 1:
                edges.append(
                    Hyperedge(
                        id=f"topic:{topic}",
                        relation="shares-topic",
                        node_ids=tuple(paper_ids),
                        metadata={"topic": topic},
                    )
                )
        return edges
