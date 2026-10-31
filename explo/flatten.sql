-- Module 4.1 — Aplatir le JSON brut en trois tables d'exploration.
-- Source : raw.openfda_drug_event (une ligne par signalement, colonne JSON `report`).
-- Exécution : bq query --location=EU --use_legacy_sql=false < explo/flatten.sql


-- 1. explo.reports : 1 ligne par signalement (dernière version chargée)
create or replace table `pharmaco-openfda-pg.explo.reports` as
select
    safety_report_id,
    receive_date,
    json_value(report, '$.serious') = '1' as is_serious,
    json_value(report, '$.seriousnessdeath') = '1' as is_death,
    json_value(report, '$.seriousnesshospitalization') = '1' as is_hospitalization,
    json_value(report, '$.seriousnesslifethreatening') = '1' as is_life_threatening,
    json_value(report, '$.seriousnessdisabling') = '1' as is_disabling,
    json_value(report, '$.occurcountry') as occur_country,
    json_value(report, '$.primarysource.qualification') as reporter_qualification,
    json_value(report, '$.patient.patientsex') as patient_sex,
    safe_cast(json_value(report, '$.patient.patientonsetage') as float64) as patient_age,
    json_value(report, '$.patient.patientonsetageunit') as patient_age_unit
from `pharmaco-openfda-pg.raw.openfda_drug_event`
qualify row_number() over (partition by safety_report_id order by ingested_at desc) = 1;


-- 2. explo.report_drugs : 1 ligne par médicament d'un signalement
create or replace table `pharmaco-openfda-pg.explo.report_drugs` as
with latest as (
    select safety_report_id, report
    from `pharmaco-openfda-pg.raw.openfda_drug_event`
    qualify row_number() over (partition by safety_report_id order by ingested_at desc) = 1
)
select
    safety_report_id,
    drug_position,
    -- nom déclaré nettoyé : majuscules, espaces multiples réduits, point final retiré
    regexp_replace(
        regexp_replace(upper(trim(json_value(drug, '$.medicinalproduct'))), r'\s+', ' '),
        r'\.$', ''
    ) as medicinal_product,
    json_value(drug, '$.openfda.generic_name[0]') as generic_name,
    json_value(drug, '$.openfda.brand_name[0]') as brand_name,
    json_value(drug, '$.openfda.manufacturer_name[0]') as manufacturer_name,
    json_value(drug, '$.openfda.pharm_class_epc[0]') as pharm_class,
    json_value(drug, '$.drugcharacterization') as drug_role,  -- 1 suspect, 2 concomitant, 3 interaction
    coalesce(
        json_value(drug, '$.openfda.route[0]'),
        json_value(drug, '$.drugadministrationroute')
    ) as administration_route
from latest,
    unnest(json_query_array(report, '$.patient.drug')) as drug with offset as drug_position;


-- 3. explo.report_reactions : 1 ligne par réaction d'un signalement
create or replace table `pharmaco-openfda-pg.explo.report_reactions` as
with latest as (
    select safety_report_id, report
    from `pharmaco-openfda-pg.raw.openfda_drug_event`
    qualify row_number() over (partition by safety_report_id order by ingested_at desc) = 1
)
select
    safety_report_id,
    reaction_position,
    upper(trim(json_value(reaction, '$.reactionmeddrapt'))) as reaction,
    json_value(reaction, '$.reactionoutcome') as reaction_outcome  -- 1 rétabli … 5 fatal, 6 inconnu
from latest,
    unnest(json_query_array(report, '$.patient.reaction')) as reaction with offset as reaction_position;


-- Vérification des volumes
select 'reports' as table_name, count(*) as row_count from `pharmaco-openfda-pg.explo.reports`
union all
select 'report_drugs', count(*) from `pharmaco-openfda-pg.explo.report_drugs`
union all
select 'report_reactions', count(*) from `pharmaco-openfda-pg.explo.report_reactions`;
