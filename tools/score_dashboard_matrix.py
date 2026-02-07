"""Simple weighted scorer for 4-engine dashboard benchmark matrix."""

weights = {
    "performance": 25,
    "simplicity": 20,
    "cross_platform": 15,
    "telepresence": 15,
    "ecosystem": 10,
    "cost": 10,
    "ai": 5,
}

scores = {
    "threejs": {"performance": 23, "simplicity": 17, "cross_platform": 13, "telepresence": 12, "ecosystem": 10, "cost": 9, "ai": 4},
    "r3f": {"performance": 21, "simplicity": 16, "cross_platform": 13, "telepresence": 12, "ecosystem": 9, "cost": 8, "ai": 4},
    "needle": {"performance": 20, "simplicity": 18, "cross_platform": 14, "telepresence": 13, "ecosystem": 7, "cost": 8, "ai": 3},
    "playcanvas": {"performance": 22, "simplicity": 18, "cross_platform": 15, "telepresence": 14, "ecosystem": 8, "cost": 9, "ai": 4},
}


def total(engine: str) -> int:
    return sum(scores[engine][k] for k in weights)


if __name__ == "__main__":
    ranked = sorted(((name, total(name)) for name in scores), key=lambda x: x[1], reverse=True)
    for name, t in ranked:
        print(f"{name}: {t}")
