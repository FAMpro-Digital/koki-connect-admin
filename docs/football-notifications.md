# Module Football — règles des notifications de changement d'horaire

Statut : **règles documentées, calcul de priorité implémenté et testé ; envoi NON implémenté.**
La table `public.koki_notifications` n'est **pas** modifiée à ce stade.

## 1. Ce qui existe déjà (branche `feature/module-football`)

- Un déclencheur sur `koki_foot.matchs` inscrit dans `koki_foot.changements_horaire` chaque changement
  d'heure d'un **match publié**, que la correction vienne d'un administrateur ou du fournisseur.
  Une seule ligne est créée par couple (ancienne heure, nouvelle heure) : un import répété n'en crée
  pas d'autre.
- Chaque ligne reçoit une **priorité**, calculée par `koki_foot.priorite_horaire()` au moment de
  l'inscription. Le calcul est testé (section 27 de `supabase/tests/foot.sql`).
- Un match non publié n'inscrit rien.

## 2. Règles de priorité (heure de Koki = Africa/Dakar)

Les règles s'appliquent dans cet ordre ; la première qui correspond l'emporte.

| Ordre | Situation | Priorité | Envoi prévu |
|---|---|---|---|
| 1 | Match **reporté**, ou nouvelle heure un **autre jour** à Koki (passage de minuit compris) | `prioritaire` | Immédiat, push et SMS si l'abonné les a acceptés |
| 2 | Match qui commence dans les **60 prochaines minutes** (ancienne ou nouvelle heure), quel que soit l'écart | `normale` | Immédiat (push) |
| 3 | Écart **inférieur à 5 min** | `aucune` | Pas d'envoi ; l'heure est simplement mise à jour dans l'application |
| 4 | Écart **de 5 à 14 min** | `facultative` | Seulement pour les abonnés qui ont choisi « tous les changements » ; regroupable dans un résumé |
| 5 | Écart **de 15 min ou plus** (en avance ou en retard) | `normale` | Immédiat (push) |

La règle des 60 minutes ne s'applique qu'à un match qui n'a pas encore commencé : pour un match
passé, c'est l'écart seul qui décide.

## 3. Principes pour le futur module d'envoi

1. **Idempotence**
   - Clé d'envoi : (`changements_horaire.id`, destinataire, canal). Une contrainte d'unicité en
     base empêche tout second envoi, même si la tâche est relancée.
   - Le module marque `traite_le` une fois le changement traité. Une ligne déjà traitée n'est
     jamais renvoyée.
   - **Changements successifs** (16:00 → 16:30 → 17:00) : seul le dernier changement non traité
     est envoyé, avec l'heure initiale et l'heure finale. Les changements intermédiaires sont
     marqués traités sans envoi.
   - **Retour à l'heure initiale** avant tout envoi : rien n'est envoyé.
2. **Rappels déjà programmés** (par exemple « le match commence dans 1 h ») : ils sont recalculés
   à partir de la nouvelle heure ; l'ancien rappel est annulé avant son envoi.
3. **Préférences de l'abonné** (à stocker dans le futur module, pas dans `koki_notifications`) :
   - suivre un match, une équipe ou une compétition ;
   - niveau : « importants seulement » (prioritaire et normale) ou « tous les changements »
     (facultative en plus) ;
   - canaux : push, SMS (SMS seulement pour `prioritaire`, par souci de coût) ;
   - heures calmes (par exemple 22 h à 7 h) : les priorités `normale` et `facultative` sont
     reportées au matin ; `prioritaire` passe toujours.
4. **Désabonnement**
   - un lien ou bouton « Ne plus suivre » dans chaque notification ;
   - un réglage global « Aucune notification sportive » ;
   - un désabonnement prend effet avant le prochain envoi, et aucun message n'est envoyé pour
     confirmer le désabonnement.
5. **Contenu** : nom des équipes, ancienne et nouvelle heure à Koki, et la mention « horaire
   corrigé par Koki Connect » quand l'origine est manuelle. Aucune donnée personnelle.
6. **Limitation** : au plus 3 notifications par match et par abonné en 24 h, hors `prioritaire`.

## 4. Ce qu'il faudra valider avant d'implémenter l'envoi

- la structure des préférences (nouvelle table du module, sans modifier `public.koki_notifications`) ;
- l'usage du SMS (coût) et les heures calmes ;
- le lien avec le module de notifications existant (`api/notifications-dispatch.js`).
