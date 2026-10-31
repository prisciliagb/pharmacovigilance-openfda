-- Module 4.2 — Les 30 questions sur les tables explo (créées par explo/flatten.sql).
-- « Médicament suspect » : drug_role = '1'.
-- Nom de médicament : nom générique openFDA s'il existe, sinon nom déclaré nettoyé.
-- Les indicateurs comptent des signalements, pas un risque.


-- =========================================================================
-- Débutant
-- =========================================================================

-- Q1. Nombre de signalements par année de réception
select extract(year from receive_date) as receive_year, count(*) as report_count
from `pharmaco-openfda-pg.explo.reports`
group by receive_year
order by receive_year;

-- Q2. Les 20 signalements les plus récents de patients de plus de 80 ans (âge en années)
select safety_report_id, receive_date, patient_age, patient_sex, is_serious
from `pharmaco-openfda-pg.explo.reports`
where patient_age_unit = '801' and patient_age > 80
order by receive_date desc, safety_report_id
limit 20;

-- Q3. Signalements graves et non graves, part de graves
select
    countif(is_serious) as serious_count,
    countif(not is_serious) as non_serious_count,
    round(100 * countif(is_serious) / count(*), 1) as serious_pct
from `pharmaco-openfda-pg.explo.reports`;

-- Q4. Les 10 pays avec le plus de signalements
select occur_country, count(*) as report_count
from `pharmaco-openfda-pg.explo.reports`
where occur_country is not null
group by occur_country
order by report_count desc
limit 10;

-- Q5. Répartition par sexe avec libellés
select
    case patient_sex when '1' then 'Homme' when '2' then 'Femme' else 'Inconnu' end as sex,
    count(*) as report_count
from `pharmaco-openfda-pg.explo.reports`
group by sex
order by report_count desc;

-- Q6. Les 15 réactions les plus déclarées
select reaction, count(distinct safety_report_id) as report_count
from `pharmaco-openfda-pg.explo.report_reactions`
group by reaction
order by report_count desc
limit 15;

-- Q7. Les 10 médicaments les plus souvent cités comme suspects
select
    coalesce(generic_name, medicinal_product) as drug_name,
    count(distinct safety_report_id) as report_count
from `pharmaco-openfda-pg.explo.report_drugs`
where drug_role = '1'
group by drug_name
order by report_count desc
limit 10;

-- Q8. Médicaments dont le nom contient « INSULIN »
select medicinal_product, count(distinct safety_report_id) as report_count
from `pharmaco-openfda-pg.explo.report_drugs`
where medicinal_product like '%INSULIN%'
group by medicinal_product
order by report_count desc;


-- =========================================================================
-- Intermédiaire
-- =========================================================================

-- Q9. Taux de signalements graves des 20 médicaments suspects les plus signalés
with suspect_reports as (
    select distinct coalesce(generic_name, medicinal_product) as drug_name, safety_report_id
    from `pharmaco-openfda-pg.explo.report_drugs`
    where drug_role = '1'
)
select
    s.drug_name,
    count(*) as report_count,
    round(100 * countif(r.is_serious) / count(*), 1) as serious_pct
from suspect_reports as s
join `pharmaco-openfda-pg.explo.reports` as r using (safety_report_id)
group by s.drug_name
order by report_count desc
limit 20;

-- Q10. Évolution mensuelle des signalements et des signalements graves
select
    date_trunc(receive_date, month) as receive_month,
    count(*) as report_count,
    countif(is_serious) as serious_count
from `pharmaco-openfda-pg.explo.reports`
group by receive_month
order by receive_month;

-- Q11. Répartition par tranche d'âge (âges convertis en années)
-- Unités : 800 décennie, 801 année, 802 mois, 803 semaine, 804 jour, 805 heure
with ages as (
    select
        case patient_age_unit
            when '800' then patient_age * 10
            when '801' then patient_age
            when '802' then patient_age / 12
            when '803' then patient_age / 52
            when '804' then patient_age / 365
            when '805' then patient_age / 8760
        end as age_years
    from `pharmaco-openfda-pg.explo.reports`
)
select
    case
        when age_years is null then 'Inconnu'
        when age_years < 18 then '0-17'
        when age_years < 45 then '18-44'
        when age_years < 65 then '45-64'
        when age_years < 80 then '65-79'
        else '80+'
    end as age_group,
    count(*) as report_count
from ages
group by age_group
order by age_group;

-- Q12. Part des professionnels de santé (1 à 3) et des consommateurs (5) dans les 10 premiers pays
with top_countries as (
    select occur_country
    from `pharmaco-openfda-pg.explo.reports`
    where occur_country is not null
    group by occur_country
    order by count(*) desc
    limit 10
)
select
    occur_country,
    count(*) as report_count,
    round(100 * countif(reporter_qualification in ('1', '2', '3')) / count(*), 1) as health_professional_pct,
    round(100 * countif(reporter_qualification = '5') / count(*), 1) as consumer_pct
from `pharmaco-openfda-pg.explo.reports`
join top_countries using (occur_country)
group by occur_country
order by report_count desc;

-- Q13a. Nombre moyen de médicaments et de réactions par signalement
select
    round((select count(*) from `pharmaco-openfda-pg.explo.report_drugs`) / count(*), 2) as avg_drugs,
    round((select count(*) from `pharmaco-openfda-pg.explo.report_reactions`) / count(*), 2) as avg_reactions
from `pharmaco-openfda-pg.explo.reports`;

-- Q13b. Distribution du nombre de médicaments par signalement
with drug_counts as (
    select safety_report_id, count(*) as drug_count
    from `pharmaco-openfda-pg.explo.report_drugs`
    group by safety_report_id
)
select
    if(drug_count >= 10, '10+', cast(drug_count as string)) as drug_count_bucket,
    count(*) as report_count
from drug_counts
group by drug_count_bucket
order by min(drug_count);

-- Q14. Nombre de signalements par type de gravité, en une ligne
select
    countif(is_death) as death_count,
    countif(is_hospitalization) as hospitalization_count,
    countif(is_life_threatening) as life_threatening_count,
    countif(is_disabling) as disabling_count
from `pharmaco-openfda-pg.explo.reports`;

-- Q15. Les 10 fabricants les plus cités et leur taux de signalements avec décès
with manufacturer_reports as (
    select distinct manufacturer_name, safety_report_id
    from `pharmaco-openfda-pg.explo.report_drugs`
    where manufacturer_name is not null
)
select
    m.manufacturer_name,
    count(*) as report_count,
    round(100 * countif(r.is_death) / count(*), 1) as death_pct
from manufacturer_reports as m
join `pharmaco-openfda-pg.explo.reports` as r using (safety_report_id)
group by m.manufacturer_name
order by report_count desc
limit 10;

-- Q16. Qualité des données : signalements où le même médicament apparaît plusieurs fois
select
    safety_report_id,
    coalesce(generic_name, medicinal_product) as drug_name,
    count(*) as occurrences
from `pharmaco-openfda-pg.explo.report_drugs`
group by safety_report_id, drug_name
having count(*) > 1
order by occurrences desc
limit 100;


-- =========================================================================
-- Avancé
-- =========================================================================

-- Q17. Les 20 couples médicament suspect × réaction les plus fréquents
select
    coalesce(d.generic_name, d.medicinal_product) as drug_name,
    x.reaction,
    count(distinct d.safety_report_id) as report_count
from `pharmaco-openfda-pg.explo.report_drugs` as d
join `pharmaco-openfda-pg.explo.report_reactions` as x using (safety_report_id)
where d.drug_role = '1'
group by drug_name, x.reaction
order by report_count desc
limit 20;

-- Q18. Écart du taux de gravité de chaque médicament (≥ 500 signalements) au taux global
with suspect_reports as (
    select distinct coalesce(generic_name, medicinal_product) as drug_name, safety_report_id
    from `pharmaco-openfda-pg.explo.report_drugs`
    where drug_role = '1'
),
global_rate as (
    select countif(is_serious) / count(*) as serious_rate
    from `pharmaco-openfda-pg.explo.reports`
),
drug_rates as (
    select s.drug_name, count(*) as report_count, countif(r.is_serious) / count(*) as serious_rate
    from suspect_reports as s
    join `pharmaco-openfda-pg.explo.reports` as r using (safety_report_id)
    group by s.drug_name
    having count(*) >= 500
)
select
    d.drug_name,
    d.report_count,
    round(100 * d.serious_rate, 1) as serious_pct,
    round(100 * g.serious_rate, 1) as global_serious_pct,
    round(100 * (d.serious_rate - g.serious_rate), 1) as gap_points,
    round(100 * safe_divide(d.serious_rate - g.serious_rate, g.serious_rate), 1) as gap_pct
from drug_rates as d
cross join global_rate as g
order by gap_points desc;

-- Q19. Signalements dont le nombre de médicaments dépasse la moyenne de leur pays
with drug_counts as (
    select r.safety_report_id, r.occur_country, count(d.drug_position) as drug_count
    from `pharmaco-openfda-pg.explo.reports` as r
    left join `pharmaco-openfda-pg.explo.report_drugs` as d using (safety_report_id)
    where r.occur_country is not null
    group by r.safety_report_id, r.occur_country
)
select
    safety_report_id,
    occur_country,
    drug_count,
    round(avg(drug_count) over (partition by occur_country), 2) as country_avg
from drug_counts
qualify drug_count > avg(drug_count) over (partition by occur_country)
order by drug_count desc
limit 100;

-- Q20. Les 3 médicaments suspects les plus signalés chaque mois
with monthly as (
    select
        date_trunc(r.receive_date, month) as receive_month,
        coalesce(d.generic_name, d.medicinal_product) as drug_name,
        count(distinct d.safety_report_id) as report_count
    from `pharmaco-openfda-pg.explo.report_drugs` as d
    join `pharmaco-openfda-pg.explo.reports` as r using (safety_report_id)
    where d.drug_role = '1'
    group by receive_month, drug_name
)
select
    receive_month,
    row_number() over (partition by receive_month order by report_count desc) as month_rank,
    drug_name,
    report_count
from monthly
qualify month_rank <= 3
order by receive_month, month_rank;

-- Q21. Médicaments avec plus de 10 % de signalements comportant une réaction d'issue fatale
-- Volume minimal fixé à 100 signalements pour que le taux ait du sens.
with suspect_reports as (
    select distinct coalesce(generic_name, medicinal_product) as drug_name, safety_report_id
    from `pharmaco-openfda-pg.explo.report_drugs`
    where drug_role = '1'
),
fatal_reports as (
    select distinct safety_report_id
    from `pharmaco-openfda-pg.explo.report_reactions`
    where reaction_outcome = '5'
)
select
    s.drug_name,
    count(*) as report_count,
    count(f.safety_report_id) as fatal_report_count,
    round(100 * count(f.safety_report_id) / count(*), 1) as fatal_pct
from suspect_reports as s
left join fatal_reports as f using (safety_report_id)
group by s.drug_name
having count(*) >= 100 and count(f.safety_report_id) / count(*) > 0.10
order by fatal_pct desc;

-- Q22. Couples de médicaments les plus fréquents dans les signalements avec interaction (code 3)
with interaction_reports as (
    select distinct safety_report_id
    from `pharmaco-openfda-pg.explo.report_drugs`
    where drug_role = '3'
),
drugs as (
    select distinct safety_report_id, coalesce(generic_name, medicinal_product) as drug_name
    from `pharmaco-openfda-pg.explo.report_drugs`
    join interaction_reports using (safety_report_id)
)
select a.drug_name as drug_a, b.drug_name as drug_b, count(*) as report_count
from drugs as a
join drugs as b
    on a.safety_report_id = b.safety_report_id and a.drug_name < b.drug_name
group by drug_a, drug_b
order by report_count desc
limit 20;


-- =========================================================================
-- Expert
-- =========================================================================

-- Q23. Dernier signalement grave de chaque médicament suspect
select
    coalesce(d.generic_name, d.medicinal_product) as drug_name,
    r.safety_report_id,
    r.receive_date
from `pharmaco-openfda-pg.explo.report_drugs` as d
join `pharmaco-openfda-pg.explo.reports` as r using (safety_report_id)
where d.drug_role = '1' and r.is_serious
qualify row_number() over (
    partition by drug_name order by r.receive_date desc, r.safety_report_id desc
) = 1
order by r.receive_date desc, drug_name;

-- Q24. Croissance mensuelle et tendance (hausse / baisse)
with monthly as (
    select date_trunc(receive_date, month) as receive_month, count(*) as report_count
    from `pharmaco-openfda-pg.explo.reports`
    group by receive_month
)
select
    receive_month,
    report_count,
    lag(report_count) over (order by receive_month) as previous_month_count,
    round(100 * safe_divide(
        report_count - lag(report_count) over (order by receive_month),
        lag(report_count) over (order by receive_month)
    ), 1) as growth_pct,
    case
        when lag(report_count) over (order by receive_month) is null then null
        when report_count >= lag(report_count) over (order by receive_month) then 'hausse'
        else 'baisse'
    end as trend
from monthly
order by receive_month;

-- Q25. Par jour : signalements, cumul depuis le début de l'année, moyenne mobile 7 jours
with daily as (
    select receive_date, count(*) as report_count
    from `pharmaco-openfda-pg.explo.reports`
    group by receive_date
)
select
    receive_date,
    report_count,
    sum(report_count) over (
        partition by extract(year from receive_date) order by receive_date
    ) as ytd_count,
    round(avg(report_count) over (
        order by receive_date rows between 6 preceding and current row
    ), 1) as moving_avg_7d
from daily
order by receive_date;

-- Q26. Nombre moyen de jours entre deux signalements graves consécutifs, par médicament
with serious_dates as (
    select distinct coalesce(d.generic_name, d.medicinal_product) as drug_name, r.receive_date
    from `pharmaco-openfda-pg.explo.report_drugs` as d
    join `pharmaco-openfda-pg.explo.reports` as r using (safety_report_id)
    where d.drug_role = '1' and r.is_serious
),
gaps as (
    select
        drug_name,
        date_diff(receive_date, lag(receive_date) over (partition by drug_name order by receive_date), day) as gap_days
    from serious_dates
)
select drug_name, count(gap_days) + 1 as serious_days, round(avg(gap_days), 1) as avg_gap_days
from gaps
group by drug_name
having count(gap_days) >= 5
order by avg_gap_days, serious_days desc;

-- Q27. Segmentation des médicaments suspects en 4 niveaux de volume (NTILE)
with drug_stats as (
    select
        s.drug_name,
        count(*) as report_count,
        countif(r.is_serious) / count(*) as serious_rate
    from (
        select distinct coalesce(generic_name, medicinal_product) as drug_name, safety_report_id
        from `pharmaco-openfda-pg.explo.report_drugs`
        where drug_role = '1'
    ) as s
    join `pharmaco-openfda-pg.explo.reports` as r using (safety_report_id)
    group by s.drug_name
),
tiers as (
    select *, ntile(4) over (order by report_count) as volume_tier
    from drug_stats
)
select
    volume_tier,
    count(*) as drug_count,
    min(report_count) as min_reports,
    max(report_count) as max_reports,
    sum(report_count) as total_reports,
    round(avg(report_count), 1) as avg_reports,
    round(100 * avg(serious_rate), 1) as avg_serious_pct
from tiers
group by volume_tier
order by volume_tier;

-- Q28. Classement mensuel des classes pharmacologiques, et celles qui ont été n°1 au moins un mois
with monthly as (
    select
        date_trunc(r.receive_date, month) as receive_month,
        d.pharm_class,
        count(distinct d.safety_report_id) as report_count
    from `pharmaco-openfda-pg.explo.report_drugs` as d
    join `pharmaco-openfda-pg.explo.reports` as r using (safety_report_id)
    where d.pharm_class is not null
    group by receive_month, d.pharm_class
),
ranked as (
    select *, rank() over (partition by receive_month order by report_count desc) as month_rank
    from monthly
)
select pharm_class, count(*) as months_at_top, array_agg(receive_month order by receive_month) as months
from ranked
where month_rank = 1
group by pharm_class
order by months_at_top desc;

-- Q29. Médicaments émergents : volume du dernier trimestre ≥ 2 × même trimestre un an plus tôt
-- Ne renvoie des lignes que si l'année précédente est chargée (sinon le trimestre de référence est vide).
with quarterly as (
    select
        coalesce(d.generic_name, d.medicinal_product) as drug_name,
        date_trunc(r.receive_date, quarter) as receive_quarter,
        count(distinct d.safety_report_id) as report_count
    from `pharmaco-openfda-pg.explo.report_drugs` as d
    join `pharmaco-openfda-pg.explo.reports` as r using (safety_report_id)
    where d.drug_role = '1'
    group by drug_name, receive_quarter
),
last_quarter as (
    select max(receive_quarter) as q from quarterly
)
select
    cur.drug_name,
    cur.report_count as last_quarter_count,
    prev.report_count as year_before_count,
    round(cur.report_count / prev.report_count, 2) as ratio
from quarterly as cur
join last_quarter as lq on cur.receive_quarter = lq.q
join quarterly as prev
    on prev.drug_name = cur.drug_name
    and prev.receive_quarter = date_sub(lq.q, interval 1 year)
where cur.report_count >= 2 * prev.report_count
order by ratio desc;

-- Q30. PRR par couple médicament suspect × réaction (≥ 3 signalements), PRR ≥ 2
--   a = signalements avec D et R      b = avec D sans R
--   c = avec R sans D                 d = ni D ni R
--   PRR = [a / (a + b)] / [c / (c + d)]
with drug_reports as (
    select distinct coalesce(generic_name, medicinal_product) as drug_name, safety_report_id
    from `pharmaco-openfda-pg.explo.report_drugs`
    where drug_role = '1'
),
reaction_reports as (
    select distinct reaction, safety_report_id
    from `pharmaco-openfda-pg.explo.report_reactions`
    where safety_report_id in (select safety_report_id from drug_reports)
),
pairs as (
    select dr.drug_name, rr.reaction, count(*) as a
    from drug_reports as dr
    join reaction_reports as rr using (safety_report_id)
    group by dr.drug_name, rr.reaction
    having count(*) >= 3
),
drug_totals as (
    select drug_name, count(*) as n_drug from drug_reports group by drug_name
),
reaction_totals as (
    select reaction, count(*) as n_reaction from reaction_reports group by reaction
),
total as (
    select count(distinct safety_report_id) as n from drug_reports
)
select
    p.drug_name,
    p.reaction,
    p.a,
    dt.n_drug - p.a as b,
    rt.n_reaction - p.a as c,
    t.n - dt.n_drug - rt.n_reaction + p.a as d,
    round(safe_divide(p.a / dt.n_drug, (rt.n_reaction - p.a) / (t.n - dt.n_drug)), 2) as prr
from pairs as p
join drug_totals as dt using (drug_name)
join reaction_totals as rt using (reaction)
cross join total as t
where safe_divide(p.a / dt.n_drug, (rt.n_reaction - p.a) / (t.n - dt.n_drug)) >= 2
order by prr desc, p.a desc
limit 100;
