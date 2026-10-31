-- 1 ligne par signalement : dernière version chargée, colonnes renommées et typées.
with latest as (
    select *
    from {{ source('openfda', 'openfda_drug_event') }}
    qualify row_number() over (partition by safety_report_id order by ingested_at desc) = 1
)

select
    safety_report_id,
    receive_date,
    ingested_at,
    json_value(report, '$.serious') = '1' as is_serious,
    coalesce(json_value(report, '$.seriousnessdeath') = '1', false) as is_death,
    coalesce(json_value(report, '$.seriousnesshospitalization') = '1', false) as is_hospitalization,
    coalesce(json_value(report, '$.seriousnesslifethreatening') = '1', false) as is_life_threatening,
    coalesce(json_value(report, '$.seriousnessdisabling') = '1', false) as is_disabling,
    json_value(report, '$.occurcountry') as occur_country,
    json_value(report, '$.primarysource.qualification') as reporter_qualification,
    json_value(report, '$.patient.patientsex') as patient_sex,
    safe_cast(json_value(report, '$.patient.patientonsetage') as float64) as patient_age,
    json_value(report, '$.patient.patientonsetageunit') as patient_age_unit
from latest
