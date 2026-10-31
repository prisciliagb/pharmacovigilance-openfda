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

## Configuration GCP (Module 1)

| Ressource | Valeur |
|---|---|
| Projet | `pharmaco-openfda-pg` |
| Budget | 10 €, alertes à 50 %, 90 % et 100 % |
| Bucket (EU) | `gs://pharmaco-openfda-pg-raw` |
| Datasets BigQuery (EU) | `raw`, `explo`, `ml` ; dbt écrit dans `dbt_dev_*` |
| Compte de service | `pipeline-sa` : BigQuery Data Editor, BigQuery Job User, Storage Object Admin, Cloud Run Invoker, Secret Manager Secret Accessor |
| API activées | BigQuery, Cloud Storage, Cloud Run, Cloud Scheduler, Artifact Registry, Cloud Build, Secret Manager |

```bash
gcloud storage buckets create gs://pharmaco-openfda-pg-raw --location=EU
bq --location=EU mk -d pharmaco-openfda-pg:raw
bq --location=EU mk -d pharmaco-openfda-pg:explo
bq --location=EU mk -d pharmaco-openfda-pg:ml
gcloud iam service-accounts create pipeline-sa --display-name="Pipeline openFDA"
```

## Démarrage

```bash
uv sync
gcloud auth application-default login
cp .env.example .env   # puis renseigner OPENFDA_API_KEY
cd pharmaco && uv run dbt debug
```

## Découverte de l'API (Module 2)

`uv run python explo/api_discovery.py` — résultats au 29/10/2026 :

- Un signalement = un objet imbriqué : en-tête (dates, gravité, pays), `primarysource`, et `patient` avec deux listes `drug[]` et `reaction[]`.
- **1 319 106** signalements reçus en 2024.
- Top réactions : DRUG INEFFECTIVE, OFF LABEL USE, DEATH, NAUSEA, FATIGUE.
- Top médicaments dans les signalements avec suspect : HUMIRA, ENBREL, DUPIXENT, ZANTAC, REVLIMID.
- **178 877** signalements graves mentionnent l'ibuprofène.

## Avancement

- [x] Module 1 — Installation et configuration
- [x] Module 2 — Découverte de l'API openFDA
- [ ] Module 3 — Ingestion Python vers GCS et BigQuery
- [ ] Module 4 — Exploration SQL dans BigQuery
- [ ] Module 5 — Transformation avec dbt
