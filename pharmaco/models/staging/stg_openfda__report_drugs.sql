-- 1 ligne par médicament d'un signalement.
with latest as (
    select safety_report_id, report
    from {{ source('openfda', 'openfda_drug_event') }}
    qualify row_number() over (partition by safety_report_id order by ingested_at desc) = 1
)

select
    concat(safety_report_id, '-', cast(drug_position as string)) as report_drug_id,
    safety_report_id,
    drug_position,
    json_value(drug, '$.medicinalproduct') as medicinal_product,
    json_value(drug, '$.openfda.generic_name[0]') as generic_name,
    json_value(drug, '$.openfda.brand_name[0]') as brand_name,
    json_value(drug, '$.openfda.manufacturer_name[0]') as manufacturer_name,
    json_value(drug, '$.openfda.pharm_class_epc[0]') as pharm_class,
    json_value(drug, '$.drugcharacterization') as drug_role,
    coalesce(
        json_value(drug, '$.openfda.route[0]'),
        json_value(drug, '$.drugadministrationroute')
    ) as administration_route
from latest,
    unnest(json_query_array(report, '$.patient.drug')) as drug with offset as drug_position
