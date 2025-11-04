from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, Iterable, List, MutableMapping, Sequence, Set, Tuple


@dataclass
class Node:
    """Represents an entity in the knowledge graph."""

    id: str
    label: str
    kind: str
    metadata: MutableMapping[str, object] = field(default_factory=dict)

    def text_signature(self) -> str:
        """Return concatenated text fields used by keyword-based search."""

        description = str(self.metadata.get("description", ""))
        tags = " ".join(str(tag) for tag in self.metadata.get("tags", []))
        return f"{self.label} {self.kind} {description} {tags}".strip()


@dataclass
class Hyperedge:
    """Represents a semantic relationship connecting multiple nodes."""

    id: str
    relation: str
    node_ids: Tuple[str, ...]
    weight: float = 1.0
    metadata: MutableMapping[str, object] = field(default_factory=dict)


class KnowledgeGraph:
    """In-memory hypergraph used by the semantic search strategies."""

    def __init__(self) -> None:
        self.nodes: Dict[str, Node] = {}
        self.hyperedges: Dict[str, Hyperedge] = {}
        self._node_to_edges: Dict[str, Set[str]] = {}

    def add_node(self, node: Node) -> None:
        self.nodes[node.id] = node
        self._node_to_edges.setdefault(node.id, set())

    def add_hyperedge(self, edge: Hyperedge) -> None:
        self.hyperedges[edge.id] = edge
        for node_id in edge.node_ids:
            self._node_to_edges.setdefault(node_id, set()).add(edge.id)

    def neighbors(self, node_id: str) -> Iterable[Node]:
        for edge_id in self._node_to_edges.get(node_id, ()):  # type: ignore[arg-type]
            edge = self.hyperedges[edge_id]
            for related_id in edge.node_ids:
                if related_id != node_id and related_id in self.nodes:
                    yield self.nodes[related_id]

    def related_edges(self, node_id: str) -> Iterable[Hyperedge]:
        for edge_id in self._node_to_edges.get(node_id, ()):  # type: ignore[arg-type]
            yield self.hyperedges[edge_id]

    def all_nodes(self) -> Sequence[Node]:
        return list(self.nodes.values())

    def all_edges(self) -> Sequence[Hyperedge]:
        return list(self.hyperedges.values())

    @classmethod
    def from_sources(cls, sources: Sequence["Source"]) -> "KnowledgeGraph":
        graph = cls()
        for source in sources:
            for node in source.nodes():
                graph.add_node(node)
            for edge in source.hyperedges():
                graph.add_hyperedge(edge)
        return graph


class Source:
    """Interface for knowledge sources used to populate the graph."""

    name: str

    def nodes(self) -> Iterable[Node]:
        raise NotImplementedError

    def hyperedges(self) -> Iterable[Hyperedge]:
        raise NotImplementedError


def build_demo_graph() -> KnowledgeGraph:
    """Create a demo graph that combines local files, research papers, and web snippets."""

    from .sources.filesystem import FileSystemSource
    from .sources.science import SamplePapersSource
    from .sources.websnippets import WebSnippetSource

    sources: List[Source] = [
        FileSystemSource(root_path="docs", namespace="docs"),
        SamplePapersSource(),
        WebSnippetSource(),
    ]
    return KnowledgeGraph.from_sources(sources)
