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
ingestion/   script d'ingestion openFDA → GCS → BigQuery, SQL de la table brute
explo/       découverte de l'API, aplatissement et 30 questions SQL
pharmaco/    projet dbt (seeds, staging, intermediate, marts, tests)
Dockerfile   image du job Cloud Run
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

## Ingestion (Module 3)

[ingestion/ingest_openfda.py](ingestion/ingest_openfda.py) charge les signalements jour par jour :

1. **API** : pagination `limit`/`skip` sur `receivedate`, 404 (aucun résultat) géré, nouvelles tentatives avec attente exponentielle sur 429/5xx et erreurs réseau, timeout sur chaque requête.
2. **GCS** : JSON Lines dans `gs://pharmaco-openfda-pg-raw/openfda/drug_event/load_date=AAAA-MM-JJ/receive_date=AAAA-MM-JJ.jsonl`.
3. **BigQuery** : la partition du jour de `raw.openfda_drug_event` est remplacée (`WRITE_TRUNCATE` sur `table$AAAAMMJJ`), donc relancer un jour ne crée pas de doublon.

| Règle | Mise en œuvre |
|---|---|
| Incrémental | Reprend au dernier `receive_date` présent dans BigQuery |
| Rattrapage | Recharge toujours les 30 jours précédant le dernier jour présent (`LOOKBACK_DAYS`) |
| Idempotent | Remplacement de partition, ou suppression du jour s'il n'a plus de résultat |
| Traçable | `load_date` et `ingested_at` sur chaque ligne, fichiers GCS rangés par date de chargement |
| Paramétrable | `GCP_PROJECT`, `GCS_BUCKET`, `OPENFDA_API_KEY`, `START_DATE`, `END_DATE`, `LOOKBACK_DAYS` |
| Sécurisé | Clé dans `.env` en local, dans Secret Manager (`openfda-api-key`) sur Cloud Run |

**Volume** : le bloc `openfda` de chaque médicament contient des listes d'identifiants (`package_ndc`, `spl_id`…) qui représentent ~90 % du JSON. Seuls les champs utiles sont conservés (`generic_name`, `brand_name`, `manufacturer_name`, `pharm_class_epc`, `route`, `substance_name`), ce qui divise le volume par 4.

**Période** : openFDA publie FAERS par trimestre ; les données disponibles s'arrêtent au 30/06/2026. Le chargement initial couvre **avril à juin 2026** (~350 000 signalements) ; le job quotidien récupère les jours suivants dès leur publication.

```bash
# local
uv run --env-file .env python -m ingestion.ingest_openfda

# Cloud Run (job openfda-ingest, europe-west1), planifié à 6 h par Cloud Scheduler (openfda-daily)
gcloud run jobs execute openfda-ingest --region europe-west1
```

## Exploration SQL (Module 4)

- [explo/flatten.sql](explo/flatten.sql) aplatit le JSON en `explo.reports` (1 signalement), `explo.report_drugs` (1 médicament d'un signalement) et `explo.report_reactions` (1 réaction d'un signalement), avec `JSON_VALUE`, `JSON_QUERY_ARRAY`, `UNNEST` et `QUALIFY` pour garder la dernière version de chaque signalement.
- [explo/questions.sql](explo/questions.sql) répond aux 30 questions, du comptage simple au PRR.

## Transformation dbt (Module 5)

```
raw.openfda_drug_event
  └─ staging       stg_openfda__reports · stg_openfda__report_drugs · stg_openfda__report_reactions   (vues)
      └─ intermediate  int_drugs_normalized · int_reports_enriched                                      (vues)
          └─ marts     fct_reports (incrémental) · fct_drug_reactions · mart_monthly_kpis
                       mart_drug_safety · mart_signal_prr · ml_features_serious                           (tables)
```

- **Seeds** : libellés des codes déclarant, sexe et issue de réaction.
- **Normalisation des noms** : nom générique openFDA, sinon nom déclaré nettoyé par la macro `clean_drug_name` (parenthèses, dosages, unités, ponctuation).
- **PRR** : `mart_signal_prr` calcule le tableau de contingence a/b/c/d, le PRR et le khi-deux de Yates ; `is_signal` = PRR ≥ 2 et khi-deux ≥ 4 (Evans, 2001).
- **Tests** : `unique`/`not_null` sur toutes les clés, `accepted_values` (tranche d'âge, rôle du médicament), `relationships` (`fct_drug_reactions` → `fct_reports`), test singulier `assert_prr_positive`, fraîcheur de la source (alerte à 2 jours, erreur à 4).

```bash
cd pharmaco
uv run dbt seed
uv run dbt build
uv run dbt source freshness
uv run dbt docs generate && uv run dbt docs serve
```

## Limites

- Données déclaratives : un signalement ne prouve pas la causalité, et il n'y a pas de dénominateur (nombre de patients exposés).
- Un médicament très prescrit a mécaniquement beaucoup de signalements.
- Un signal PRR est une hypothèse à investiguer, pas une conclusion.

## Avancement

- [x] Module 1 — Installation et configuration
- [x] Module 2 — Découverte de l'API openFDA
- [x] Module 3 — Ingestion Python vers GCS et BigQuery
- [x] Module 4 — Exploration SQL dans BigQuery
- [x] Module 5 — Transformation avec dbt
