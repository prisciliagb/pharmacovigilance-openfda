-- 1 ligne par signalement : features pour prédire la gravité (Module 7).
-- Fuite de données évitée : aucune colonne de gravité (décès, hospitalisation…),
-- aucune issue de réaction, aucun terme de réaction.
with top_countries as (
    select occur_country
    from {{ ref('fct_reports') }}
    where occur_country is not null
    group by occur_country
    order by count(*) desc
    limit 20
)

select
    r.safety_report_id,
    r.receive_date,
    r.age_years,
    r.age_group,
    r.sex_label as sex,
    coalesce(r.reporter_label, 'Inconnu') as reporter_type,
    r.is_health_professional,
    if(t.occur_country is not null, r.occur_country, 'OTHER') as country_group,
    r.drug_count,
    r.suspect_drug_count,
    r.has_interaction,
    coalesce(r.primary_suspect_route, 'Inconnu') as primary_suspect_route,
    coalesce(r.primary_suspect_pharm_class, 'Inconnu') as primary_suspect_pharm_class,
    format_date('%m', r.receive_date) as receive_month,
    r.is_serious
from {{ ref('fct_reports') }} as r
left join top_countries as t using (occur_country)
where r.is_serious is not null
