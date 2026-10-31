-- Un PRR est un rapport de proportions : il doit être strictement positif.
-- Le test échoue si cette requête renvoie au moins une ligne.
select drug_reaction_pair, prr
from {{ ref('mart_signal_prr') }}
where prr <= 0
