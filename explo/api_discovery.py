"""Découverte de l'API openFDA drug/event (Module 2).

Usage : uv run python explo/api_discovery.py
La clé est lue dans la variable d'environnement OPENFDA_API_KEY (optionnelle).
"""

import json
import os

import requests

BASE_URL = "https://api.fda.gov/drug/event.json"
API_KEY = os.environ.get("OPENFDA_API_KEY")


def query(**params) -> dict:
    if API_KEY:
        params["api_key"] = API_KEY
    # requests encoderait les "+" et les ":" : on construit la query string à la main
    qs = "&".join(f"{k}={v}" for k, v in params.items())
    response = requests.get(f"{BASE_URL}?{qs}", timeout=30)
    response.raise_for_status()
    return response.json()


def describe(obj, indent: int = 0) -> None:
    """Affiche l'arborescence des clés d'un objet JSON."""
    pad = "  " * indent
    if isinstance(obj, dict):
        for key, value in obj.items():
            kind = type(value).__name__
            print(f"{pad}{key} ({kind})")
            if isinstance(value, (dict, list)):
                describe(value, indent + 1)
    elif isinstance(obj, list) and obj:
        describe(obj[0], indent)


def print_counts(title: str, results: list[dict]) -> None:
    print(f"\n{title}")
    for i, row in enumerate(results, 1):
        print(f"  {i:>2}. {row['term']:<45} {row['count']:>10,}")


def main() -> None:
    # 1. 5 signalements reçus en janvier 2025, et structure du JSON
    data = query(search="receivedate:[20250101+TO+20250131]", limit=5)
    print("1. Structure d'un signalement :")
    describe(data["results"][0])
    print("\nIdentifiants :", [r["safetyreportid"] for r in data["results"]])
    print("\nExemple complet (1er signalement) :")
    print(json.dumps(data["results"][0], indent=2)[:2000], "...")

    # 2. Nombre de signalements reçus en 2024
    data = query(search="receivedate:[20240101+TO+20241231]", limit=1)
    print(f"\n2. Signalements reçus en 2024 : {data['meta']['results']['total']:,}")

    # 3. Top 10 réactions
    data = query(count="patient.reaction.reactionmeddrapt.exact", limit=10)
    print_counts("3. Top 10 réactions déclarées :", data["results"])

    # 4. Top 10 médicaments suspects (drugcharacterization = 1)
    # Approximation : le filtre porte sur le signalement, pas sur chaque médicament,
    # donc les concomitants des signalements filtrés sont aussi comptés (exact en SQL, Module 4).
    data = query(
        search="patient.drug.drugcharacterization:1",
        count="patient.drug.medicinalproduct.exact",
        limit=10,
    )
    print_counts("4. Top 10 médicaments cités comme suspects :", data["results"])

    # 5. Signalements graves concernant l'ibuprofène
    data = query(
        search='serious:1+AND+patient.drug.openfda.generic_name:"IBUPROFEN"',
        limit=1,
    )
    print(
        f"\n5. Signalements graves avec ibuprofène : {data['meta']['results']['total']:,}"
    )


if __name__ == "__main__":
    main()
