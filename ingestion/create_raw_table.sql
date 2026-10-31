-- Table brute (Bronze) : un signalement openFDA par ligne, JSON complet non aplati.
-- L'aplatissement se fait ensuite dans dbt (couche staging).
create table if not exists `pharmaco-openfda-pg.raw.openfda_drug_event` (
    safety_report_id string not null options (description = "Identifiant du signalement (safetyreportid)"),
    receive_date date not null options (description = "Date de réception par la FDA (receivedate)"),
    load_date date not null options (description = "Date du chargement"),
    ingested_at timestamp not null options (description = "Horodatage de l'ingestion"),
    report json options (description = "Signalement complet renvoyé par l'API")
)
partition by receive_date
options (
    description = "Signalements bruts openFDA drug/event (FAERS), chargés par ingestion/ingest_openfda.py"
);
