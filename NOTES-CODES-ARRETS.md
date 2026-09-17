# Codes d'arrêt : le bit de sens

*Note de travail. Écrite le 08/09/2026, complétée le 16/09/2026 puis le
17/09/2026. Versionnée parce qu'elle porte la réserve qui justifie des codes du
référentiel : ce qu'elle avance reste à vérifier sur le terrain, protocoles
compris.*

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
| 15 | 23 | 38 | Hélène Boucher |
| 16 | 22 | 38 | Caroline Aigle |
| 17 | 21 | 38 | Cœur d'Orly |
| 18 | 20 | 38 | Aéroport d'Orly T4 |

Douze arrêts consécutifs à somme constante, puis quatre à 38. Le
décrochage tient à un trou : l'aller saute le 14, quand le retour, lui,
est continu de 19 à 35. Où le trou tombe exactement, c'est le trajet du
17/09 qui le dit — voir plus bas ; jusque-là il avait été supposé, et
supposé au mauvais endroit.

Requête pour le refaire :

```python
import json
st = json.load(open('metroreader/Data/NavigoStations.json'))['stations']
t7 = [s for s in st if s['provider_id'] == 59 and s['line_id'] == 17]
```

## Le trajet du 17/09/2026 : vingt arrêts d'affilée

La carte lue ce soir-là porte un trajet complet du T7, arrêt par arrêt,
de Domaine Chérioux au terminus et le premier arrêt du retour. C'est la
mesure la plus solide qu'on ait : une suite continue, dont le voyageur
connaît les deux bouts.

| heure | code lu | bits bas | arrêt |
|---|---:|---:|---|
| 16:00 | 32771 | 3 | Domaine Chérioux |
| 16:03 | 32772 | 4 | Moulin Vert |
| 16:04 | 32773 | 5 | Bretagne |
| 16:06 | 32774 | 6 | Auguste Perret |
| 16:08 | 32775 | 7 | Chevilly-Larue |
| 16:09 | 32776 | 8 | La Belle Épine |
| 16:11 | 32777 | 9 | Place de la Logistique |
| 16:12 | 32776 | 8 | La Belle Épine *(second exemplaire)* |
| 16:13 | 32778 | 10 | Porte de Rungis |
| 16:15 | 32779 | 11 | Saarinen |
| 16:17 | 32780 | 12 | Robert Schuman |
| 16:19 | 32781 | 13 | La Fraternelle |
| **16:21** | **32783** | **15** | **Hélène Boucher** |
| 16:24 | 32784 | 16 | Caroline Aigle |
| 16:25 | 32785 | 17 | Cœur d'Orly |
| 16:27 | 32786 | 18 | Aéroport d'Orly T4 |
| 16:32 | 19 | 19 | Porte de l'Essonne |
| 16:37 | 19 | 19 | Porte de l'Essonne |
| 16:39 | 19 | 19 | Porte de l'Essonne |
| 16:39 | 20 | 20 | Aéroport d'Orly T4, au retour |

Ce que ça établit :

- **Hélène Boucher est le 15, mesuré.** Elle tombe entre La Fraternelle
  (13) et Caroline Aigle (16), à sa place sur le terrain, et le voyageur
  la reconnaît. La réserve du 16/09 est levée — et dans l'autre sens que
  prévu : le 14 avait été déduit de la constante 37, la constante vaut 38
  dès cet arrêt.
- **Le 14 est un trou.** La séquence passe de 13 à 15 sans lui. Rien ne
  dit ce qu'il désignait ; ne rien y mettre est plus juste que d'y loger
  un arrêt au prétexte qu'il manque une place.
- **Le terminus est son propre miroir.** Porte de l'Essonne vaut 19 dans
  les deux sens : 19 + 19 = 38. D'où la seule entrée du référentiel.
- **Le bit 15 est écrit à l'envers de bout en bout.** Seize codes aller
  portent le bit, les quatre codes retour ne le portent pas. Ce n'est
  donc pas une lecture isolée qui se trompe : c'est la convention de
  cette rame, sur un trajet entier.

L'enregistrement n'est pas celui d'un voyageur qui valide vingt fois :
la carte reçoit un code à chaque arrêt desservi. À reprendre si on veut
comprendre ce que la borne écrit vraiment.

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
la ligne 17. Ce qu'il rattrape est maintenant mesuré : les validations
T7 du corpus écrivent un code qui diffère de celui du référentiel du
seul bit 15 — dans un sens comme dans l'autre.

| date | code lu | après XOR | arrêt |
|---|---:|---:|---|
| 05/01/2026 | 30 | 32798 | Chevilly-Larue |
| 08/09/2026 | 32775 | 7 | Chevilly-Larue |
| 16/09/2026 | 32771 | 3 | Domaine Chérioux |
| 17/09/2026 | 32771 … 32786 | 3 … 18 | seize arrêts d'affilée |
| 17/09/2026 | 19, 20 | 32787, 32788 | Porte de l'Essonne, Aéroport T4 |

Le référentiel note l'aller `n` et le retour `0x8000 | m`. En janvier la
carte écrit le retour sans son bit 15 ; en septembre elle écrit l'aller
avec. Huit mois séparent les deux conventions, sur trois rames
différentes.

Le bit 15 tel que la carte l'écrit ne dit donc pas le sens de façon
fiable, et le XOR ne prétend pas le dire : les deux sens partageant le
nom de l'arrêt, il ramène le bon nom, rien de plus. Le trajet du 17/09
le montre d'un bloc : vingt codes, le bit posé sur les seize de l'aller
et absent des quatre derniers, l'inverse exact de ce que note le
référentiel.

Généralisation possible, à valider : chercher le code tel quel, puis à
défaut le miroir, plutôt qu'un cas particulier sur une seule ligne.

Ce que `find` ne fait plus, en revanche, c'est se rabattre sur une autre
ligne de tram quand la course est connue. Chez la RATP, seuls les trams
portent un `line_id`, et leur code est un numéro de séquence propre à
leur ligne : le 15 est Hélène Boucher sur le T7 et Basilique de
Saint-Denis sur le T1. Chercher ailleurs revenait à tirer au sort. Sur
les 81 494 clés que les tables peuvent former, 123 rendaient ainsi un
arrêt d'une autre ligne ; elles rendent maintenant le nombre brut, et
aucune réponse de la ligne demandée n'est perdue.

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

Corrigé le 16/09 **en 14 et 32791**, les deux trous du bloc, avec cette
réserve : que 3 et 32802 soient Domaine Chérioux était prouvé par le
voyage du 16/09 ; que 14 et 32791 soient Hélène Boucher ne l'était pas.
Le modèle séquentiel les désignait, 14 + 23 = 37 tombant sur la
constante de la ligne, et aucune validation du corpus ne portait ces
codes.

### Ce que le terrain a répondu

Le lendemain, 17/09, le trajet complet ci-dessus. La moitié déduite était
fausse : **l'aller est 15, pas 14**, et la constante vaut 38 dès cet
arrêt, pas 37. La moitié retour tenait — 32791 est bien Hélène Boucher,
le retour étant continu de 19 à 35.

L'erreur ne venait pas du modèle mais de l'endroit où on a supposé le
trou : entre La Fraternelle et Hélène Boucher, pas entre Hélène Boucher
et Caroline Aigle. Une place manquante ne dit pas laquelle.

Entre-temps, le 32783 lu à 16:21 ne trouvait rien dans le bloc T7 et
`find` allait le chercher sur les autres lignes : la validation s'est
affichée **Baron Le Roy**, sur le T3a, à dix kilomètres de là. Le garde-fou
décrit plus haut vient de cet affichage.

`build_data.py verify` refuse un fichier où un même code porte deux noms
sur une même ligne. Il ne voit pas, en revanche, le cas inverse — un trou
dans un bloc numéroté, qu'une autre ligne vient combler. C'est l'app qui
s'en garde désormais, en rendant le nombre brut.
