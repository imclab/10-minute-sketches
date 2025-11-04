from __future__ import annotations

import os
from pathlib import Path
from typing import Iterable, List

from ..data import Hyperedge, Node, Source


class FileSystemSource(Source):
    """Build graph nodes from the local file system."""

    def __init__(self, root_path: str, namespace: str = "fs") -> None:
        self.root = Path(root_path)
        self.namespace = namespace
        self.name = f"filesystem:{self.root}"

    def nodes(self) -> Iterable[Node]:
        nodes: List[Node] = []
        if not self.root.exists():
            return nodes
        for path in self.root.rglob("*"):
            if path.is_file():
                rel_path = path.relative_to(self.root)
                node_id = f"{self.namespace}:{rel_path}".replace(os.sep, "/")
                nodes.append(
                    Node(
                        id=node_id,
                        label=rel_path.name,
                        kind="file",
                        metadata={
                            "description": path.read_text(errors="ignore")[:400],
                            "path": str(path),
                            "tags": [self.namespace, path.suffix.lstrip(".")],
                        },
                    )
                )
        return nodes

    def hyperedges(self) -> Iterable[Hyperedge]:
        edges: List[Hyperedge] = []
        if not self.root.exists():
            return edges
        for directory in {path.parent for path in self.root.rglob("*") if path.is_file()}:
            child_nodes: List[str] = []
            for file_path in directory.iterdir():
                if file_path.is_file():
                    rel_path = file_path.relative_to(self.root)
                    child_nodes.append(f"{self.namespace}:{rel_path}".replace(os.sep, "/"))
            if child_nodes:
                edge_id = f"{self.namespace}:dir:{directory.relative_to(self.root)}".replace(os.sep, "/")
                edges.append(
                    Hyperedge(
                        id=edge_id,
                        relation="contains",
                        node_ids=tuple(child_nodes),
                        metadata={"directory": str(directory)},
                    )
                )
        return edges
