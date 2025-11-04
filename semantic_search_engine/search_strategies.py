from __future__ import annotations

import math
from collections import Counter, defaultdict
from dataclasses import dataclass
from typing import Dict, List, Sequence, Tuple

from .data import KnowledgeGraph, Node


@dataclass
class SearchResult:
    node: Node
    score: float
    strategy: str


class SearchStrategy:
    """Base class for semantic search strategies."""

    name: str

    def search(self, graph: KnowledgeGraph, query: str, limit: int = 5) -> List[SearchResult]:
        raise NotImplementedError


class VectorSemanticSearch(SearchStrategy):
    """TF-IDF style vector search across node descriptions."""

    def __init__(self) -> None:
        self.name = "vector"
        self._idf: Dict[str, float] = {}

    def _build_index(self, nodes: Sequence[Node]) -> None:
        doc_count = len(nodes)
        term_doc_frequency: Dict[str, int] = defaultdict(int)
        for node in nodes:
            terms = set(self._tokenize(node.text_signature()))
            for term in terms:
                term_doc_frequency[term] += 1
        self._idf = {term: math.log((doc_count + 1) / (freq + 1)) + 1 for term, freq in term_doc_frequency.items()}

    def _tokenize(self, text: str) -> List[str]:
        return [token.lower() for token in text.split() if token.strip()]

    def _score(self, node: Node, query_terms: List[str]) -> float:
        tokens = self._tokenize(node.text_signature())
        counts = Counter(tokens)
        score = 0.0
        for term in query_terms:
            tf = counts.get(term, 0)
            if tf:
                score += (1 + math.log(tf)) * self._idf.get(term, 0.0)
        return score

    def search(self, graph: KnowledgeGraph, query: str, limit: int = 5) -> List[SearchResult]:
        nodes = graph.all_nodes()
        if not self._idf:
            self._build_index(nodes)
        query_terms = self._tokenize(query)
        scored = [SearchResult(node=node, score=self._score(node, query_terms), strategy=self.name) for node in nodes]
        scored.sort(key=lambda r: r.score, reverse=True)
        return [result for result in scored if result.score > 0][:limit]


class GraphTraversalSearch(SearchStrategy):
    """Ranks nodes based on proximity to keyword matches in the graph."""

    def __init__(self, walk_depth: int = 2) -> None:
        self.name = "graph"
        self.walk_depth = walk_depth

    def search(self, graph: KnowledgeGraph, query: str, limit: int = 5) -> List[SearchResult]:
        keywords = {token.lower() for token in query.split() if token.strip()}
        base_scores: Dict[str, float] = {}
        for node in graph.all_nodes():
            signature = node.text_signature().lower()
            if any(keyword in signature for keyword in keywords):
                base_scores[node.id] = 1.0

        propagation: Dict[str, float] = defaultdict(float)
        frontier = list(base_scores.items())
        for _ in range(self.walk_depth):
            next_frontier: List[Tuple[str, float]] = []
            for node_id, score in frontier:
                for neighbor in graph.neighbors(node_id):
                    propagated = score * 0.6
                    if propagated > 0.01:
                        if propagated > propagation[neighbor.id]:
                            propagation[neighbor.id] = max(propagation[neighbor.id], propagated)
                        next_frontier.append((neighbor.id, propagated))
            frontier = next_frontier

        combined_scores = defaultdict(float)
        for node_id, score in base_scores.items():
            combined_scores[node_id] += score
        for node_id, score in propagation.items():
            combined_scores[node_id] = max(combined_scores[node_id], score)

        results: List[SearchResult] = [
            SearchResult(node=graph.nodes[node_id], score=score, strategy=self.name)
            for node_id, score in combined_scores.items()
        ]
        results.sort(key=lambda r: r.score, reverse=True)
        return results[:limit]


class OntologyLensSearch(SearchStrategy):
    """Applies tag-based filters and boosts to match ontology facets."""

    def __init__(self) -> None:
        self.name = "ontology"

    def search(self, graph: KnowledgeGraph, query: str, limit: int = 5) -> List[SearchResult]:
        filters = [segment.strip().lower() for segment in query.split(" and ") if segment.strip()]
        results: List[SearchResult] = []
        for node in graph.all_nodes():
            tags = [str(tag).lower() for tag in node.metadata.get("tags", [])]
            match_count = sum(1 for filt in filters if any(filt in tag for tag in tags))
            if match_count:
                score = match_count / len(filters)
                results.append(SearchResult(node=node, score=score, strategy=self.name))
        results.sort(key=lambda r: r.score, reverse=True)
        return results[:limit]


class HybridSelfImprovingSearch(SearchStrategy):
    """Combines other strategies and adapts weights based on evaluation feedback."""

    def __init__(self, strategies: Sequence[SearchStrategy]) -> None:
        self.name = "hybrid"
        self.strategies = list(strategies)
        self.weights: Dict[str, float] = {strategy.name: 1.0 for strategy in strategies}

    def search(self, graph: KnowledgeGraph, query: str, limit: int = 5) -> List[SearchResult]:
        strategy_results: Dict[str, List[SearchResult]] = {}
        for strategy in self.strategies:
            strategy_results[strategy.name] = strategy.search(graph, query, limit)
        score_by_node: Dict[str, float] = defaultdict(float)
        node_obj: Dict[str, Node] = {}
        for name, results in strategy_results.items():
            weight = self.weights.get(name, 1.0)
            for rank, result in enumerate(results, start=1):
                contribution = weight / rank
                score_by_node[result.node.id] += contribution
                node_obj[result.node.id] = result.node
        merged = [SearchResult(node=node_obj[node_id], score=score, strategy=self.name) for node_id, score in score_by_node.items()]
        merged.sort(key=lambda r: r.score, reverse=True)
        return merged[:limit]

    def update_weights(self, performance: Dict[str, float], learning_rate: float = 0.1) -> None:
        for name, delta in performance.items():
            current = self.weights.get(name, 1.0)
            self.weights[name] = max(0.1, current + learning_rate * delta)
