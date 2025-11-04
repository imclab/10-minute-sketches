from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Iterable, List, Sequence

from .data import KnowledgeGraph
from .search_strategies import HybridSelfImprovingSearch, SearchResult, SearchStrategy


@dataclass
class QueryExample:
    query: str
    relevant_ids: Sequence[str]


class SearchLeague:
    """Runs evaluation rounds where strategies compete and the hybrid model self-adjusts."""

    def __init__(
        self,
        graph: KnowledgeGraph,
        strategies: Sequence[SearchStrategy],
        evaluation_set: Iterable[QueryExample],
    ) -> None:
        self.graph = graph
        self.strategies = list(strategies)
        self.evaluation_set = list(evaluation_set)
        self.hybrid = HybridSelfImprovingSearch(self.strategies)

    def _precision_at_k(self, results: Sequence[SearchResult], relevant_ids: Sequence[str], k: int = 5) -> float:
        top_k = results[:k]
        if not top_k:
            return 0.0
        relevant = {node_id for node_id in relevant_ids}
        hits = sum(1 for result in top_k if result.node.id in relevant)
        return hits / len(top_k)

    def run_round(self) -> Dict[str, float]:
        """Evaluate each strategy, update the hybrid weights, and return scores."""

        performance: Dict[str, float] = {strategy.name: 0.0 for strategy in self.strategies}
        hybrid_performance: Dict[str, float] = {strategy.name: 0.0 for strategy in self.strategies}

        for example in self.evaluation_set:
            for strategy in self.strategies:
                results = strategy.search(self.graph, example.query)
                score = self._precision_at_k(results, example.relevant_ids)
                performance[strategy.name] += score
            hybrid_results = self.hybrid.search(self.graph, example.query)
            score = self._precision_at_k(hybrid_results, example.relevant_ids)
            for strategy in self.strategies:
                # Compare hybrid score to individual strategy score for this query
                individual_score = self._precision_at_k(
                    strategy.search(self.graph, example.query), example.relevant_ids
                )
                hybrid_performance[strategy.name] += score - individual_score

        # Normalize by number of queries
        query_count = max(len(self.evaluation_set), 1)
        for name in performance:
            performance[name] /= query_count
            hybrid_performance[name] /= query_count

        self.hybrid.update_weights(hybrid_performance)
        return performance

    def champion(self) -> SearchStrategy:
        """Return the currently best performing strategy after a round."""

        scores = self.run_round()
        best_name = max(scores, key=scores.get)
        for strategy in self.strategies:
            if strategy.name == best_name:
                return strategy
        return self.hybrid


def build_demo_league(graph: KnowledgeGraph) -> SearchLeague:
    """Construct a league with canned evaluation queries spanning multiple domains."""

    from .search_strategies import GraphTraversalSearch, OntologyLensSearch, VectorSemanticSearch

    strategies: List[SearchStrategy] = [
        VectorSemanticSearch(),
        GraphTraversalSearch(),
        OntologyLensSearch(),
    ]
    evaluation_set = [
        QueryExample(query="deep learning transformers", relevant_ids=["paper:attention_is_all_you_need"]),
        QueryExample(query="file specification api", relevant_ids=["web:spec:openapi"]),
        QueryExample(query="biology protein folding", relevant_ids=["paper:alphafold"]),
    ]
    return SearchLeague(graph=graph, strategies=strategies, evaluation_set=evaluation_set)
