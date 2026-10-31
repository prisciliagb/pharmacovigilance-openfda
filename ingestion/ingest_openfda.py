"""Ingestion quotidienne openFDA drug/event → GCS → BigQuery (Module 3).

Pour chaque jour de réception à charger :
  1. récupère tous les signalements du jour dans l'API (pagination limit/skip) ;
  2. les dépose en JSON Lines dans GCS, rangés par date de chargement ;
  3. remplace la partition du jour dans BigQuery par le contenu du fichier.

Usage local :
    uv run --env-file .env python -m ingestion.ingest_openfda

Variables d'environnement :
    GCP_PROJECT      projet GCP (obligatoire)
    GCS_BUCKET       bucket du data lake (obligatoire)
    OPENFDA_API_KEY  clé openFDA (recommandée : 120 000 requêtes/jour au lieu de 1 000)
    START_DATE       premier jour à charger si la table est vide (défaut 2026-04-01)
    END_DATE         dernier jour à charger (défaut : hier)
    LOOKBACK_DAYS    jours rechargés systématiquement avant le dernier jour présent (défaut 30)
"""

import json
import logging
import os
import time
from datetime import UTC, date, datetime, timedelta

import requests
from google.cloud import bigquery, storage

API_URL = "https://api.fda.gov/drug/event.json"
PAGE_SIZE = 1000  # maximum autorisé par openFDA
MAX_SKIP = 25000  # au-delà, openFDA refuse le paramètre skip
MAX_RETRIES = 5
TIMEOUT_SECONDS = 60

# Champs conservés dans le bloc openfda de chaque médicament. Les autres (package_ndc,
# spl_id, spl_set_id…) sont des listes d'identifiants qui pèsent ~90 % du JSON sans servir l'analyse.
OPENFDA_FIELDS_KEPT = {
    "generic_name",
    "brand_name",
    "manufacturer_name",
    "pharm_class_epc",
    "route",
    "substance_name",
}

DATASET = "raw"
TABLE = "openfda_drug_event"
GCS_PREFIX = "openfda/drug_event"

SCHEMA = [
    bigquery.SchemaField("safety_report_id", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("receive_date", "DATE", mode="REQUIRED"),
    bigquery.SchemaField("load_date", "DATE", mode="REQUIRED"),
    bigquery.SchemaField("ingested_at", "TIMESTAMP", mode="REQUIRED"),
    bigquery.SchemaField("report", "JSON"),
]

log = logging.getLogger("ingest_openfda")


# --- API openFDA -----------------------------------------------------------


def get_page(day: date, skip: int, api_key: str | None) -> dict | None:
    """Appelle l'API pour une page ; None si aucun résultat (404)."""
    d = day.strftime("%Y%m%d")
    # construite à la main : requests encoderait les "+" et les crochets
    url = f"{API_URL}?search=receivedate:[{d}+TO+{d}]&limit={PAGE_SIZE}&skip={skip}"
    if api_key:
        url += f"&api_key={api_key}"

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = requests.get(url, timeout=TIMEOUT_SECONDS)
        except (requests.ConnectionError, requests.Timeout) as exc:
            error = f"{type(exc).__name__}"
        else:
            if response.status_code == 404:  # openFDA : aucun résultat
                return None
            if response.status_code == 200:
                return response.json()
            if response.status_code != 429 and response.status_code < 500:
                response.raise_for_status()  # 4xx autre que 429 : inutile de réessayer
            error = f"HTTP {response.status_code}"

        wait = 2**attempt
        log.warning(
            "%s le %s (skip=%d), tentative %d/%d, attente %ds",
            error,
            day,
            skip,
            attempt,
            MAX_RETRIES,
            wait,
        )
        time.sleep(wait)

    raise RuntimeError(
        f"Échec de l'API openFDA pour le {day} (skip={skip}) après {MAX_RETRIES} tentatives"
    )


def fetch_day(day: date, api_key: str | None) -> list[dict]:
    """Récupère tous les signalements reçus un jour donné."""
    reports: list[dict] = []
    skip = 0
    while True:
        page = get_page(day, skip, api_key)
        if page is None:
            break
        total = page["meta"]["results"]["total"]
        if total > MAX_SKIP + PAGE_SIZE:
            raise RuntimeError(
                f"{total} signalements le {day} : trop pour paginer avec skip"
            )
        reports.extend(slim_report(r) for r in page["results"])
        skip += PAGE_SIZE
        if not page["results"] or skip >= total:
            break
    return reports


def slim_report(report: dict) -> dict:
    """Ne garde que les champs utiles du bloc openfda de chaque médicament."""
    for drug in report.get("patient", {}).get("drug", []):
        if "openfda" in drug:
            drug["openfda"] = {
                k: v for k, v in drug["openfda"].items() if k in OPENFDA_FIELDS_KEPT
            }
    return report


# --- GCS et BigQuery -------------------------------------------------------


def to_jsonl(
    reports: list[dict], day: date, load_date: date, ingested_at: datetime
) -> str:
    rows = (
        {
            "safety_report_id": r["safetyreportid"],
            "receive_date": day.isoformat(),
            "load_date": load_date.isoformat(),
            "ingested_at": ingested_at.isoformat(),
            "report": r,
        }
        for r in reports
    )
    return "\n".join(json.dumps(row, ensure_ascii=False) for row in rows)


def upload_to_gcs(
    bucket: storage.Bucket, content: str, day: date, load_date: date
) -> str:
    path = f"{GCS_PREFIX}/load_date={load_date.isoformat()}/receive_date={day.isoformat()}.jsonl"
    bucket.blob(path).upload_from_string(content, content_type="application/x-ndjson")
    return f"gs://{bucket.name}/{path}"


def replace_partition(bq: bigquery.Client, table_id: str, uri: str, day: date) -> None:
    """Remplace la partition du jour : relancer pour un jour donne le même résultat."""
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        schema=SCHEMA,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    # le décorateur $AAAAMMJJ cible une seule partition : WRITE_TRUNCATE ne vide qu'elle
    partition = f"{table_id}${day.strftime('%Y%m%d')}"
    bq.load_table_from_uri(uri, partition, job_config=job_config).result()


def delete_partition(bq: bigquery.Client, table_id: str, day: date) -> None:
    """Jour sans signalement : on s'assure qu'il ne reste rien d'un ancien chargement."""
    query = f"delete from `{table_id}` where receive_date = @day"
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("day", "DATE", day)]
    )
    bq.query(query, job_config=job_config).result()


def last_loaded_day(bq: bigquery.Client, table_id: str) -> date | None:
    rows = bq.query(f"select max(receive_date) as last_day from `{table_id}`").result()
    return next(iter(rows)).last_day


# --- Orchestration ---------------------------------------------------------


def days_to_load(
    last_day: date | None, start_date: date, end_date: date, lookback_days: int
) -> list[date]:
    """Jours manquants + fenêtre de rattrapage (openFDA met à jour les jours récents)."""
    if last_day is None:
        first = start_date
    else:
        first = max(start_date, last_day - timedelta(days=lookback_days - 1))
    return [first + timedelta(days=i) for i in range((end_date - first).days + 1)]


def main() -> None:
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
    )

    project = os.environ["GCP_PROJECT"]
    bucket_name = os.environ["GCS_BUCKET"]
    api_key = os.environ.get("OPENFDA_API_KEY") or None
    start_date = date.fromisoformat(os.environ.get("START_DATE", "2026-04-01"))
    lookback_days = int(os.environ.get("LOOKBACK_DAYS", "30"))
    yesterday = datetime.now(UTC).date() - timedelta(days=1)
    end_date = (
        date.fromisoformat(os.environ["END_DATE"])
        if os.environ.get("END_DATE")
        else yesterday
    )

    if not api_key:
        log.warning("OPENFDA_API_KEY absente : limite de 1 000 requêtes par jour")

    bq = bigquery.Client(project=project)
    bucket = storage.Client(project=project).bucket(bucket_name)
    table_id = f"{project}.{DATASET}.{TABLE}"

    last_day = last_loaded_day(bq, table_id)
    days = days_to_load(last_day, start_date, end_date, lookback_days)
    if not days:
        log.info("Rien à charger (dernier jour présent : %s)", last_day)
        return
    log.info(
        "Dernier jour présent : %s → chargement du %s au %s (%d jours)",
        last_day,
        days[0],
        days[-1],
        len(days),
    )

    load_date = datetime.now(UTC).date()
    total = 0
    for day in days:
        ingested_at = datetime.now(UTC)
        reports = fetch_day(day, api_key)
        if reports:
            uri = upload_to_gcs(
                bucket, to_jsonl(reports, day, load_date, ingested_at), day, load_date
            )
            replace_partition(bq, table_id, uri, day)
        else:
            delete_partition(bq, table_id, day)
        total += len(reports)
        log.info("%s : %d signalements chargés", day, len(reports))

    log.info("Terminé : %d signalements sur %d jours", total, len(days))


if __name__ == "__main__":
    main()
