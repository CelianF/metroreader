# Codes d'arrêt : le bit de sens

*Note de travail. Écrite le 08/09/2026, complétée le 16/09/2026. Versionnée
parce qu'elle porte la réserve qui justifie des codes du référentiel : ce
qu'elle avance reste à vérifier sur le terrain, protocoles compris.*

## La question

Sur le TVM, les arrêts relevés à la main tombent dans deux familles :
des petits nombres (722 à 729) et des nombres au-dessus de 32768
(32782, 32843, 33502, 33759). Hypothèse de départ : **un bit de poids
fort marque le sens retour.**

## Ce qui est prouvé

Le T7 est la seule ligne dont le référentiel contient les deux sens.
Les mêmes arrêts y figurent deux fois, une fois sans le bit 15, une
fois avec :

| aller | retour | somme | arrêt |
|---:|---:|---:|---|
| 2 | 35 | 37 | Lamartine |
| 3 | 34 | 37 | Domaine Chérioux |
| 4 | 33 | 37 | Moulin Vert |
| 5 | 32 | 37 | Bretagne |
| 6 | 31 | 37 | Auguste Perret |
| 7 | 30 | 37 | Chevilly-Larue |
| 8 | 29 | 37 | La Belle Épine |
| 9 | 28 | 37 | Place de la Logistique |
| 10 | 27 | 37 | Porte de Rungis |
| 11 | 26 | 37 | Saarinen |
| 12 | 25 | 37 | Robert Schuman |
| 13 | 24 | 37 | La Fraternelle |
| 16 | 22 | 38 | Caroline Aigle |
| 17 | 21 | 38 | Cœur d'Orly |
| 18 | 20 | 38 | Aéroport d'Orly T4 |

Douze arrêts consécutifs à somme constante. Le décrochage à 38 sur les
trois derniers vient de la branche d'Orly, dont le nombre d'arrêts
diffère entre les deux sens.

Requête pour le refaire :

```python
import json
st = json.load(open('metroreader/Data/NavigoStations.json'))
t7 = [s for s in st if s['provider_id'] == 59 and s['line_id'] == 17]
```

## Le modèle

- **Bit 15 (0x8000) posé = sens retour.** Confirmé.
- Les 15 bits bas sont un **compteur séquentiel le long de la ligne**.
  L'aller numérote 1…N ; le retour **continue** à N+1 et remonte la
  ligne à l'envers.
- Conséquence : pour un même arrêt, `aller + retour = constante`.

Ce n'est donc **pas** « le même code avec un bit en plus ». Les deux
sens ont des codes distincts ; le bit 15 est redondant avec la plage,
mais il est bien là.

## Prédictions à vérifier sur le TVM

Codes aller relevés, dans l'ordre réel de l'itinéraire vers l'ouest :

| aller | arrêt | source de la saisie |
|---:|---|---|
| 722 | Mairie | GPS |
| 723 | Le Delta | GPS |
| 724 | Parc Médicis | **liste de la ligne** |
| 725 | Montjean | GPS |
| 726 | Le Clos la Garenne | **liste de la ligne** |
| 727 | Le Petit Fresnes | **liste de la ligne** |
| 728 | Docteur Ténine | **liste de la ligne** |
| 729 | Berny - Raymond Aron | **liste de la ligne** |

Le 33502 annoncé Montjean donne `734 + 725 = 1459`. Ça suppose que
l'aller s'arrête à 729 et que le retour démarre à 730 sur Berny —
cohérent si La Croix de Berny, terminus, est hors bloc.

**Codes retour attendus :**

| arrêt | aller | retour attendu |
|---|---:|---:|
| Berny - Raymond Aron | 729 | **33498** |
| Docteur Ténine | 728 | **33499** |
| Le Petit Fresnes | 727 | **33500** |
| Le Clos la Garenne | 726 | **33501** |
| Montjean | 725 | 33502 *(observé)* |
| Parc Médicis | 724 | **33503** |
| Le Delta | 723 | **33504** |
| Mairie | 722 | **33505** |

### Protocole

Prendre le TVM vers l'est et valider à **Docteur Ténine** ou **Le Petit
Fresnes** — les deux arrêts dont la saisie aller vient de la liste de
la ligne, donc sûre. Si le code lu est 33499 ou 33500, le modèle tient
et la constante 1459 est calée.

Si le code est décalé d'un ou deux, la constante est fausse mais le
modèle reste bon : recaler avec `C = aller + retour` sur cette mesure.

## Ce qui cloche

**L'ancrage repose sur une saisie GPS.** Montjean a été identifié
depuis la suggestion « arrêt le plus proche », pas depuis la liste de
la ligne. Le modèle est prouvé, son calage sur le TVM ne l'est pas.

**32843 ne rentre nulle part.** Bits bas 75, annoncé Chevilly-Larue,
comme 32782 (bits bas 14) et 13. Trois codes TVM pour un même arrêt,
dont aucun ne tombe dans le bloc 722-737. Les trois viennent de
suggestions GPS prises au même endroit en six minutes — au moins un est
mal identifié. À reprendre proprement.

**0 = La Croix de Berny RER** est suspect : 0 sert habituellement à
dire « non renseigné ».

**Les blocs ne sont pas par ligne.** 13 et 722-729 ne peuvent pas
cohabiter dans un compteur 1…N sur une ligne de 32 arrêts. La
numérotation semble être à l'échelle du réseau, par blocs attribués
aux sections. À creuser.

## Piste côté code

`NavigoStations.find` porte un `location_id ^ 0x8000` codé en dur pour
la ligne 17. Ce qu'il rattrape est maintenant mesuré : les trois
validations T7 du corpus écrivent un code qui diffère de celui du
référentiel du seul bit 15 — dans un sens comme dans l'autre.

| date | code lu | après XOR | arrêt |
|---|---:|---:|---|
| 05/01/2026 | 30 | 32798 | Chevilly-Larue |
| 08/09/2026 | 32775 | 7 | Chevilly-Larue |
| 16/09/2026 | 32771 | 3 | Domaine Chérioux |

Le référentiel note l'aller `n` et le retour `0x8000 | m`. En janvier la
carte écrit le retour sans son bit 15 ; en septembre elle écrit l'aller
avec. Huit mois séparent les deux conventions, sur trois rames
différentes.

Le bit 15 tel que la carte l'écrit ne dit donc pas le sens de façon
fiable, et le XOR ne prétend pas le dire : les deux sens partageant le
nom de l'arrêt, il ramène le bon nom, rien de plus.

La lecture du 16/09 est la seule dont le voyageur connaisse l'arrêt : il
est entré à Domaine Chérioux, ce que le XOR donne bien.

Généralisation possible, à valider : chercher le code tel quel, puis à
défaut le miroir, plutôt qu'un cas particulier sur une seule ligne.

## Hélène Boucher portait les codes de Domaine Chérioux

Cette entrée du 16/09 s'affichait pourtant « Hélène Boucher (Orlytech) ».
Le XOR faisait son travail — 32771 → 3 — mais deux arrêts du bloc T7
portaient le code 3, et `find` rend le premier du fichier.

Le bloc T7 est saisi à la main. IDFM publie pour ces arrêts un
`privatecode` à cinq chiffres — 63727 et 63745 pour Domaine Chérioux,
63738 et 63756 pour Hélène Boucher — sans rapport avec les numéros de
séquence qu'écrit la carte. Il est rangé par paires (aller, retour), en
ordre alphabétique inverse, et Hélène Boucher y suit immédiatement
Domaine Chérioux : ses deux nombres, 3 et 32802, étaient la copie exacte
de ceux du voisin.

**Corrigé en 14 et 32791**, les deux trous du bloc. Avec cette réserve :
que 3 et 32802 soient Domaine Chérioux est prouvé, par le voyage du
16/09. Que 14 et 32791 soient Hélène Boucher ne l'est pas — c'est le
modèle séquentiel qui les désigne, 14 + 23 = 37 tombant sur la constante
de la ligne, et aucune validation du corpus ne porte ces codes.

### Protocole

Valider à Hélène Boucher (Orlytech). Selon le sens et la génération du
valideur, quatre nombres peuvent sortir : 14 ou 32782 à l'aller, 23 ou
32791 au retour. Les quatre tombent sur le bon arrêt une fois 14 et
32791 dans la table, par le code tel quel ou par son miroir. Un
cinquième nombre infirmerait le placement, pas le modèle : recaler avec
`C = aller + retour = 37`.

`build_data.py verify` refuse désormais un fichier où un même code porte
deux noms sur une même ligne.
