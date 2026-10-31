-- 1 ligne par réaction d'un signalement.
with latest as (
    select safety_report_id, report
    from {{ source('openfda', 'openfda_drug_event') }}
    qualify row_number() over (partition by safety_report_id order by ingested_at desc) = 1
)

select
    concat(safety_report_id, '-', cast(reaction_position as string)) as report_reaction_id,
    safety_report_id,
    reaction_position,
    upper(trim(json_value(reaction, '$.reactionmeddrapt'))) as reaction,
    json_value(reaction, '$.reactionoutcome') as reaction_outcome
from latest,
    unnest(json_query_array(report, '$.patient.reaction')) as reaction with offset as reaction_position
