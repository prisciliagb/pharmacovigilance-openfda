-- 1 ligne par signalement, enrichi : âge en années, tranche d'âge, libellés,
-- nombre de médicaments et de réactions, médicament suspect principal.
with reports as (
    select * from {{ ref('stg_openfda__reports') }}
),

drug_counts as (
    select
        safety_report_id,
        count(*) as drug_count,
        countif(is_suspect) as suspect_drug_count,
        logical_or(drug_role = '3') as has_interaction
    from {{ ref('int_drugs_normalized') }}
    group by safety_report_id
),

primary_suspect as (
    select safety_report_id, drug_name, pharm_class, administration_route
    from {{ ref('int_drugs_normalized') }}
    where is_suspect
    qualify row_number() over (partition by safety_report_id order by drug_position) = 1
),

reaction_counts as (
    select safety_report_id, count(*) as reaction_count
    from {{ ref('stg_openfda__report_reactions') }}
    group by safety_report_id
),

ages as (
    select
        safety_report_id,
        case patient_age_unit
            when '800' then patient_age * 10
            when '801' then patient_age
            when '802' then patient_age / 12
            when '803' then patient_age / 52
            when '804' then patient_age / 365
            when '805' then patient_age / 8760
        end as age_years
    from reports
)

select
    r.safety_report_id,
    r.receive_date,
    r.ingested_at,
    r.is_serious,
    r.is_death,
    r.is_hospitalization,
    r.is_life_threatening,
    r.is_disabling,
    r.occur_country,
    r.reporter_qualification,
    q.reporter_label,
    coalesce(q.is_health_professional, false) as is_health_professional,
    r.patient_sex,
    coalesce(s.sex_label, 'Inconnu') as sex_label,
    -- âges hors de 0-120 ans considérés comme erreurs de saisie
    if(a.age_years between 0 and 120, round(a.age_years, 1), null) as age_years,
    case
        when a.age_years is null or a.age_years not between 0 and 120 then 'Inconnu'
        when a.age_years < 18 then '0-17'
        when a.age_years < 45 then '18-44'
        when a.age_years < 65 then '45-64'
        when a.age_years < 80 then '65-79'
        else '80+'
    end as age_group,
    coalesce(d.drug_count, 0) as drug_count,
    coalesce(d.suspect_drug_count, 0) as suspect_drug_count,
    coalesce(d.has_interaction, false) as has_interaction,
    coalesce(x.reaction_count, 0) as reaction_count,
    p.drug_name as primary_suspect_drug,
    p.pharm_class as primary_suspect_pharm_class,
    p.administration_route as primary_suspect_route
from reports as r
left join ages as a using (safety_report_id)
left join drug_counts as d using (safety_report_id)
left join primary_suspect as p using (safety_report_id)
left join reaction_counts as x using (safety_report_id)
left join {{ ref('ref_reporter_qualification') }} as q on r.reporter_qualification = q.code
left join {{ ref('ref_patient_sex') }} as s on r.patient_sex = s.code
