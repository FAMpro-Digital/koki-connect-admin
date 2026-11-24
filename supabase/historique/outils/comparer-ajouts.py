#!/usr/bin/env python3
"""Compare deux empreintes de structure : AVANT (production) et APRÈS migrations Football.
Réussit seulement si chaque objet existant est INCHANGÉ et toujours présent ; les ajouts doivent tous
appartenir au module Football (schéma koki_foot, fonctions public.koki_foot_*). Liste les ajouts."""
import sys
def lire(f):
    d={}
    for l in open(f,encoding='utf8'):
        l=l.rstrip('\n')
        if l: t,nom,h=l.split('|',2); d[(t,nom)]=h
    return d
# Mêmes exclusions que comparer.py : fonction interne de la plateforme et tâches cron (propres à chaque environnement).
ignore=lambda k:k==('fonction','public.rls_auto_enable()') or k[0]=='cron'
avant,apres=[{k:v for k,v in lire(f).items() if not ignore(k)} for f in sys.argv[1:3]]
modifies=[k for k in avant if k in apres and apres[k]!=avant[k]]
supprimes=[k for k in avant if k not in apres]
ajouts=sorted(k for k in apres if k not in avant)
football=lambda nom:nom.startswith('koki_foot') or nom.startswith('public.koki_foot_') or '.koki_foot' in nom or nom=='koki_foot'
etrangers=[k for k in ajouts if not football(k[1])]
for t,n in modifies: print('MODIFIÉ   ',t,n)
for t,n in supprimes: print('SUPPRIMÉ  ',t,n)
for t,n in etrangers: print('AJOUT HORS MODULE',t,n)
par={} 
for t,_ in ajouts: par[t]=par.get(t,0)+1
print('existants inchangés : %d/%d | ajouts Football : %s' % (len(avant)-len(modifies)-len(supprimes),len(avant),', '.join('%s %d'%(t,n) for t,n in sorted(par.items()))))
sys.exit(1 if modifies or supprimes or etrangers else 0)
