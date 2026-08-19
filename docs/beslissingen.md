# Architectuurbeslissingen

Dit document legt vast waarom een aantal ontwerpkeuzes in RingRing Logger
zijn zoals ze zijn — vooral de keuzes die er in de code uitzien als vrij
afstembare constanten, maar die in werkelijkheid privacy-garanties zijn.
Wie een van deze terugdraait zonder de reden te kennen, breekt het
ontwerp stilletjes: de app blijft compileren en testen slagen mogelijk
nog, maar de garantie die de gebruiker denkt te krijgen klopt niet meer.

## 1. Corridor-claims in plaats van routes

**Beslissing** — Alleen een per-wegvak samenvatting (corridor/uur/modaliteit)
verlaat het toestel, nooit een reeks coördinaten.

**Waarom** — Vier tijd-locatiepunten identificeren al ~95% van individuen
(De Montjoye et al.). Een aaneengesloten reeks segmenten IS een route, en
een route is bijna altijd herleidbaar naar een persoon.

**Wat breekt als je dit terugdraait** — Zodra geserialiseerde claims
coördinaten of een geordende segmentreeks bevatten, is de DELEN-flow in de
praktijk een trackingfeed, ongeacht de versleuteling eromheen.

**Waar in de code** — `lib/quill/claims.dart`, `lib/delen/envelope_codec.dart`.
De test in `test/quill/claims_test.dart` ("serialized claims never contain
coordinate keys") bewaakt dit.

## 2. Trimmen vóór het matchen, niet erna

**Beslissing** — De route wordt aan begin en eind ingekort (`trimRouteEnds`)
vóórdat matching tegen de corridorregistry plaatsvindt.

**Waarom** — Claims rond vertrek en aankomst verraden woon- en werkadres.
Ze mogen niet ontstaan en achteraf gefilterd worden — ze moeten nooit
bestaan.

**Wat breekt als je dit terugdraait** — Matchen vóór trimmen produceert
corridor-claims vlak bij het start- en eindpunt van de rit, wat het hele
punt van trimmen ondermijnt.

**Waar in de code** — `lib/delen/delen_screen.dart` (`_makeEnvelopes` roept
`trimRouteEnds` aan vóór `matchTrip`), `lib/delen/geo_utils.dart`.

Bekende zwakte: `trimRouteEnds` telt cumulatieve padlengte, dus GPS-ruis
tijdens stilstand vult de 300 m alvast op. Verplaatsing vanaf het
startpunt zou correcter zijn.

## 3. Vers wegwerp-keypair per envelop

**Beslissing** — Twee onafhankelijke ephemeral keys per envelop (één voor
de rumor, één voor de wrap), nooit hergebruikt.

**Waarom** — Hergebruik van een key over enveloppen heen maakt claims van
één rit direct linkbaar aan elkaar, ook zonder de inhoud te ontsleutelen.

**Wat breekt als je dit terugdraait** — Een relay-operator of afluisteraar
kan enveloppen met dezelfde afzenderkey aan elkaar koppelen en zo alsnog
een route reconstrueren uit losse corridor-claims.

**Waar in de code** — `lib/delen/delen_screen.dart` (`_postOne`),
`lib/delen/envelope_codec.dart`.

## 4. NIP-59 gift wrap, dubbele NIP-44-versleuteling

**Beslissing** — Elke claim wordt eerst verzegeld (seal) en dan
gewikkeld (gift wrap), beide keren NIP-44-versleuteld.

**Waarom** — De relay is architectonisch onvertrouwd. Bescherming moet
komen van versleuteling, niet van relay-beleid — een AUTH-gate is beleid
van de operator en verdwijnt zodra iemand de database kopieert.

**Wat breekt als je dit terugdraait** — Zonder de dubbele laag ligt
metadata (afzender, ontvanger, timing) van de rumor bloot voor iedereen
met leestoegang tot de relay-database, niet alleen voor de bedoelde
ontvanger.

**Waar in de code** — `lib/delen/envelope_codec.dart`.

## 5. Rumor-created_at op UTC-middernacht van de claimdatum

**Beslissing** — De `created_at` van de rumor wordt vastgezet op
UTC-middernacht van de claimdatum, niet op het echte tijdstip van posten.

**Waarom** — Tijdresolutie is bewust de dag; het uur zit apart in een tag.
Een echte kloktijd in de rumor maakt claims van één rit onderling
koppelbaar voor wie ze uitpakt.

**Wat breekt als je dit terugdraait** — Een ontvanger die meerdere claims
van dezelfde afzender uitpakt, kan ze aan de hand van de kloktijd weer tot
één rit aan elkaar rijgen — precies wat corridor-claims (zie beslissing 1)
moeten voorkomen.

**Waar in de code** — `lib/delen/envelope_codec.dart`.

## 6. hourBucket in lokale tijd

**Beslissing** — De uur-bucket van een claim wordt bepaald in lokale tijd,
niet in UTC.

**Waarom** — Spits is een lokaal begrip; gemeenten aggregeren op lokale
uren, niet op UTC-uren.

**Wat breekt als je dit terugdraait** — Aggregaties op gemeenteniveau
schuiven een of twee uur op ten opzichte van de werkelijke spits, wat het
hele nut van de uur-bucket ondermijnt. Vastgelegd gevolg dat blijft
bestaan: bij de zomertijdwissel ontstaat een dubbel uur 2 en een
ontbrekend uur 3. De Mailroom aggregeert hierop, dus dit is geen vrije
keuze meer.

**Waar in de code** — `lib/quill/claims.dart`.

## 7. Contributor-tag: HMAC(vaultSecret, corridorId | date)

**Beslissing** — Elke claim krijgt een contributor-tag: een
HMAC-SHA256 van corridor-ID en datum, gekeyed met een lokaal
vault-secret.

**Waarom** — Zonder deze tag telt een k-drempel enveloppen in plaats van
bijdragers; één toestel dat twee keer post verschijnt dan als twee
mensen.

**Wat breekt als je dit terugdraait** — k-anonimiteitsdrempels op
corridor/uur/dag-niveau worden onbetrouwbaar, omdat een enkel toestel de
telling kunstmatig kan ophogen. Bewuste afweging: binnen één corridor én
één dag is de tag een stabiel pseudoniem, over corridors en dagen heen
niet — dat is opzettelijk, geen lek.

**Waar in de code** — `lib/delen/contributor_tag.dart`,
`lib/delen/envelope_codec.dart`.

## 8. Gespreid posten

**Beslissing** — Enveloppen worden niet allemaal tegelijk gepost, maar met
een willekeurige vertraging tot `postDelayMaxSec` verspreid.

**Waarom** — Enveloppen die tegelijk aankomen zijn te clusteren op
aankomsttijd, ongeacht de versleuteling — dat is een correlatie-aanval
die niets met de inhoud van de claim te maken heeft.

**Wat breekt als je dit terugdraait** — Alle claims van één rit komen
binnen dezelfde seconde bij de relay binnen en zijn daardoor als groep
herkenbaar, ook zonder ze te ontsleutelen.

**Waar in de code** — `lib/delen/delen_screen.dart` (`_postAll`),
`lib/ringring_config.dart`.

`postDelayMaxSec` staat nu op 30 seconden en is te kort; spreiding over
uren hoort erbij. Dit is een bekende, nog niet opgeloste zwakte.

## 9. Snelheidsdrempels als proxy voor modaliteit

**Beslissing** — Modaliteit wordt afgeleid uit snelheidsdrempels
(`classifyModality`), niet uit sensordata.

**Waarom** — Expliciet een tijdelijke oplossing: de sensorgebaseerde
vierklassen-classifier is er nog niet.

**Wat breekt als je dit terugdraait** — Niets breekt door dit terug te
draaien, want er is niets om naar terug te draaien — dit IS de
noodoplossing. Vervangen zonder de bekende fout te kennen levert wel een
regressie op.

**Waar in de code** — `lib/quill/claims.dart`, `lib/quill/params.dart`.

Bekende fout: `classifyModality` stemt op mediane vensters terwijl de
claim `v85` rapporteert, waardoor drukke kruispunten naar "other"
kantelen.

## 10. lib/quill/ blijft Flutter-vrij

**Beslissing** — `lib/quill/` mag nergens `package:flutter` importeren.

**Waarom** — De engine moet zonder Flutter kunnen draaien, voor tests en
tooling buiten de Flutter-toolchain.

**Wat breekt als je dit terugdraait** — Tests en tooling die de engine
puur via `dart test`/`dart run` aanroepen, breken zodra er ergens in
`lib/quill/` een Flutter-import binnensluipt.

**Waar in de code** — Bewaakt door `test/quill/no_flutter_import_test.dart`.
Let op: `lib/models/trip.dart` importeert wél Flutter (`IconData` in
enums) — daarom bestaat `tool/parse_points.dart` als tijdelijke omweg.
