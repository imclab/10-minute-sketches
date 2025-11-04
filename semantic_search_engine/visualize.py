from __future__ import annotations

import json
from typing import Dict, List

from .data import KnowledgeGraph


def hypergraph_to_json(graph: KnowledgeGraph) -> str:
    """Serialize the knowledge graph into a JSON structure for visualization clients."""

    payload: Dict[str, List[Dict[str, object]]] = {"nodes": [], "hyperedges": []}
    for node in graph.all_nodes():
        payload["nodes"].append(
            {
                "id": node.id,
                "label": node.label,
                "kind": node.kind,
                "metadata": dict(node.metadata),
            }
        )
    for edge in graph.all_edges():
        payload["hyperedges"].append(
            {
                "id": edge.id,
                "relation": edge.relation,
                "node_ids": edge.node_ids,
                "weight": edge.weight,
                "metadata": dict(edge.metadata),
            }
        )
    return json.dumps(payload, indent=2)
