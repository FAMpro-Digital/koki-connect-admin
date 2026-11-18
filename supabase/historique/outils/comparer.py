"""Compare deux empreintes de structure (categorie|objet|empreinte).

Ignorés : la fonction interne Supabase rls_auto_enable (créée par la
plateforme), les tâches planifiées (cron), propres à chaque environnement,
et le marqueur de la base de test (koki_private.test_environment).
Code de sortie 1 s'il reste un écart.
"""
import sys
from collections import defaultdict


def charger(chemin):
    d = defaultdict(list)
    for ligne in open(chemin, encoding="utf-8"):
        ligne = ligne.rstrip("\n")
        if not ligne:
            continue
        c, o, h = ligne.split("|")
        d[(c, o)].append(h)
    return {k: sorted(v) for k, v in d.items()}


def ignore(k):
    # Le marqueur « KOKI TEST » n'existe que sur la base de test.
    return k == ("fonction", "public.rls_auto_enable()") or k[0] == "cron" or "koki_private.test_environment" in k[1]


prod, local = charger(sys.argv[1]), charger(sys.argv[2])
ecarts, identiques = [], 0
for k in sorted(set(prod) | set(local)):
    if ignore(k):
        continue
    if k not in local:
        ecarts.append("absent en local : " + "|".join(k))
    elif k not in prod:
        ecarts.append("absent en production : " + "|".join(k))
    elif prod[k] != local[k]:
        ecarts.append("différent : " + "|".join(k))
    else:
        identiques += 1
for e in ecarts:
    print(e)
print(f"identiques {identiques} | écarts {len(ecarts)}")
sys.exit(1 if ecarts else 0)
