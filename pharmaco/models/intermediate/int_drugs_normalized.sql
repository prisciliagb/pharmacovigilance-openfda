-- 1 ligne par signalement × médicament harmonisé.
-- Nom harmonisé : nom générique openFDA s'il existe, sinon nom déclaré nettoyé.
-- Si un médicament apparaît plusieurs fois dans un signalement, on garde son rôle le plus fort
-- (suspect > concomitant > interaction > non administré).
with drugs as (
    select
        *,
        coalesce(upper(trim(generic_name)), {{ clean_drug_name('medicinal_product') }}) as drug_name
    from {{ ref('stg_openfda__report_drugs') }}
)

select
    concat(safety_report_id, '|', drug_name) as report_drug_key,
    safety_report_id,
    drug_name,
    drug_role,
    drug_role = '1' as is_suspect,
    medicinal_product,
    generic_name,
    brand_name,
    manufacturer_name,
    pharm_class,
    administration_route,
    drug_position
from drugs
where drug_name is not null
qualify row_number() over (
    partition by safety_report_id, drug_name
    order by coalesce(drug_role, '9'), drug_position
) = 1
