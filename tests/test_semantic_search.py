from semantic_search_engine.data import build_demo_graph
from semantic_search_engine.search_strategies import (
    GraphTraversalSearch,
    OntologyLensSearch,
    VectorSemanticSearch,
)
from semantic_search_engine.self_improver import build_demo_league


def test_vector_search_ranks_transformer_paper_first():
    graph = build_demo_graph()
    strategy = VectorSemanticSearch()
    results = strategy.search(graph, "deep learning transformers", limit=3)
    top_ids = [result.node.id for result in results]
    assert "paper:attention_is_all_you_need" in top_ids


def test_graph_search_propagates_related_results():
    graph = build_demo_graph()
    strategy = GraphTraversalSearch(walk_depth=2)
    results = strategy.search(graph, "protein", limit=5)
    ids = [result.node.id for result in results]
    assert "paper:alphafold" in ids


def test_ontology_search_matches_tags():
    graph = build_demo_graph()
    strategy = OntologyLensSearch()
    results = strategy.search(graph, "deep learning and overview", limit=5)
    ids = {result.node.id for result in results}
    assert "web:wikipedia:deep_learning" in ids


def test_search_league_runs_and_returns_scores():
    graph = build_demo_graph()
    league = build_demo_league(graph)
    scores = league.run_round()
    assert set(scores) == {"vector", "graph", "ontology"}
    assert all(score >= 0 for score in scores.values())
    champion = league.champion()
    assert champion.name in scores
