-- 1 ligne par couple médicament suspect × réaction (au moins 3 signalements).
-- Tableau de contingence sur les signalements ayant au moins un médicament suspect :
--               réaction R   autres réactions
--   médicament D     a              b
--   autres           c              d
-- PRR = [a / (a + b)] / [c / (c + d)] ; khi-deux avec correction de Yates.
-- Signal (Evans, 2001) : PRR >= 2, khi-deux >= 4, a >= 3. Un signal est une hypothèse, pas une preuve.
with pairs as (
    select drug_name, reaction, count(distinct safety_report_id) as a
    from {{ ref('fct_drug_reactions') }}
    group by drug_name, reaction
    having count(distinct safety_report_id) >= 3
),

drug_totals as (
    select drug_name, count(distinct safety_report_id) as n_drug
    from {{ ref('fct_drug_reactions') }}
    group by drug_name
),

reaction_totals as (
    select reaction, count(distinct safety_report_id) as n_reaction
    from {{ ref('fct_drug_reactions') }}
    group by reaction
),

total as (
    select count(distinct safety_report_id) as n
    from {{ ref('fct_drug_reactions') }}
),

contingency as (
    select
        p.drug_name,
        p.reaction,
        p.a,
        dt.n_drug - p.a as b,
        rt.n_reaction - p.a as c,
        t.n - dt.n_drug - rt.n_reaction + p.a as d,
        t.n
    from pairs as p
    join drug_totals as dt using (drug_name)
    join reaction_totals as rt using (reaction)
    cross join total as t
),

stats as (
    select
        *,
        safe_divide(safe_divide(a, a + b), safe_divide(c, c + d)) as prr,
        safe_divide(
            n * pow(greatest(abs(a * d - b * c) - n / 2, 0), 2),
            -- en float64 : le produit de quatre effectifs dépasse la capacité d'un INT64
            cast(a + b as float64) * (c + d) * (a + c) * (b + d)
        ) as chi_square
    from contingency
)

select
    concat(drug_name, '|', reaction) as drug_reaction_pair,
    drug_name,
    reaction,
    a as report_count,
    b,
    c,
    d,
    round(prr, 3) as prr,
    round(chi_square, 3) as chi_square,
    coalesce(prr >= 2 and chi_square >= 4, false) as is_signal
from stats
-- c = 0 : réaction jamais déclarée avec un autre médicament, PRR non calculable
where prr is not null
