-- 1 ligne par médicament suspect : volume, taux de gravité et de décès, écart au taux global.
with suspect_reports as (
    select
        d.drug_name,
        d.pharm_class,
        d.manufacturer_name,
        r.is_serious,
        r.is_death
    from {{ ref('int_drugs_normalized') }} as d
    join {{ ref('fct_reports') }} as r using (safety_report_id)
    where d.is_suspect
),

global_rates as (
    select
        safe_divide(countif(is_serious), count(*)) as global_serious_rate,
        safe_divide(countif(is_death), count(*)) as global_death_rate
    from {{ ref('fct_reports') }}
),

drugs as (
    select
        drug_name,
        approx_top_count(pharm_class, 1)[safe_offset(0)].value as pharm_class,
        approx_top_count(manufacturer_name, 1)[safe_offset(0)].value as top_manufacturer,
        count(*) as report_count,
        countif(is_serious) as serious_count,
        countif(is_death) as death_count
    from suspect_reports
    group by drug_name
)

select
    d.drug_name,
    d.pharm_class,
    d.top_manufacturer,
    d.report_count,
    d.serious_count,
    d.death_count,
    round(safe_divide(d.serious_count, d.report_count), 4) as serious_rate,
    round(safe_divide(d.death_count, d.report_count), 4) as death_rate,
    round(g.global_serious_rate, 4) as global_serious_rate,
    round(safe_divide(d.serious_count, d.report_count) - g.global_serious_rate, 4) as serious_rate_gap,
    round(safe_divide(d.death_count, d.report_count) - g.global_death_rate, 4) as death_rate_gap
from drugs as d
cross join global_rates as g
