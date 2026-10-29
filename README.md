# Pharmacovigilance openFDA

Pipeline de pharmacovigilance de bout en bout sur les signalements d'effets indésirables de médicaments publiés par la FDA (base FAERS, API openFDA `drug/event`).

> Données déclaratives FAERS : un signalement n'établit pas de lien de causalité. Tous les indicateurs parlent de **signalements**, jamais de risque.

## Architecture

```
Cloud Scheduler (6 h) → Cloud Run Job (Python) → GCS (JSON brut) → BigQuery raw
                                                                       │
                                     dbt : staging → intermediate → marts
```

| Couche | Où | Contenu |
|---|---|---|
| Bronze | GCS + dataset `raw` | JSON de l'API tel quel, une ligne par signalement |
| Silver | `staging`, `intermediate` | JSON aplati, typé, dédoublonné, noms de médicaments normalisés |
| Gold | `marts` | Faits et KPI pour l'analyse et le ML |

## Stack

Python 3.12 · uv · Google Cloud Storage · BigQuery · Cloud Run Jobs · Cloud Scheduler · Secret Manager · dbt Core

## Structure

```
ingestion/   script d'ingestion openFDA → GCS → BigQuery
explo/       découverte de l'API et exploration SQL
pharmaco/    projet dbt
```

## Démarrage

```bash
uv sync
gcloud auth application-default login
cp .env.example .env   # puis renseigner OPENFDA_API_KEY
```

## Avancement

- [x] Module 1 — Installation et configuration
- [ ] Module 2 — Découverte de l'API openFDA
- [ ] Module 3 — Ingestion Python vers GCS et BigQuery
- [ ] Module 4 — Exploration SQL dans BigQuery
- [ ] Module 5 — Transformation avec dbt
