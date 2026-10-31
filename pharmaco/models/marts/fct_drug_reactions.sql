-- 1 ligne par couple médicament suspect × réaction × signalement.
with suspects as (
    select safety_report_id, drug_name
    from {{ ref('int_drugs_normalized') }}
    where is_suspect
),

reactions as (
    select
        safety_report_id,
        reaction,
        logical_or(reaction_outcome = '5') as is_fatal_outcome
    from {{ ref('stg_openfda__report_reactions') }}
    where reaction is not null
    group by safety_report_id, reaction
)

select
    concat(s.safety_report_id, '|', s.drug_name, '|', x.reaction) as drug_reaction_key,
    s.safety_report_id,
    r.receive_date,
    s.drug_name,
    x.reaction,
    x.is_fatal_outcome,
    r.is_serious
from suspects as s
join reactions as x using (safety_report_id)
join {{ ref('fct_reports') }} as r using (safety_report_id)
