"""Run the semantic search league demo."""

from semantic_search_engine.data import build_demo_graph
from semantic_search_engine.self_improver import build_demo_league
from semantic_search_engine.visualize import hypergraph_to_json


def main() -> None:
    graph = build_demo_graph()
    league = build_demo_league(graph)

    print("Running evaluation round...")
    scores = league.run_round()
    for name, score in scores.items():
        print(f"Strategy {name}: precision@5={score:.2f}")

    champion = league.champion()
    print(f"Current champion strategy: {champion.name}")

    print("\nSample visualization payload snippet:")
    json_payload = hypergraph_to_json(graph)
    print(json_payload[:400] + "...")


if __name__ == "__main__":
    main()
