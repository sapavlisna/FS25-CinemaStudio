# FS25 Cinema Studio

Editor kamery pro filmové záběry ve Farming Simulatoru 25 bez HUD: kamera po K-framech nebo v režimech kolem cíle
(orbit, dronie, sledování…), vozidla a postavy na trasách s akcemi v přesném čase a scéna, kterou každé přehrání vrátí
na začátek.

Camera editor for cinematic shots in Farming Simulator 25 without HUD: a keyframed camera or modes around a target
(orbit, dronie, follow…), vehicles and characters on routes with timed actions, and a scene that every playback resets.

Beta: všechno je otestované automatickými testy, ve hře zatím jen část. Chyby prosím hlas v Issues.

Beta: everything is covered by automated tests, but only part of it was tried in the game. Please report bugs in Issues.

## Nápověda / Guide

**[Průvodce s ukázkami / Guide with examples](https://sapavlisna.github.io/FS25-CinemaStudio/)** – česky i anglicky (přepínač CZ/EN nahoře): editor na první
pohled, první záběr krok za krokem, herci, všech 17 režimů kamery, akce, časová osa, recepty a všechny klávesy.
Stejný průvodce je v zipu módu ve složce `manual` a ve zdrojích v
[`FS25_CinemaStudio/manual/index.html`](FS25_CinemaStudio/manual/index.html).

In Czech and English (CZ/EN switch at the top): the editor at a glance, a first shot step by step, actors, all 17
camera modes, actions, the timeline, recipes and all shortcuts. The same guide is in the `manual` folder of the mod zip.

### Rychlý start / Quick start

1. Postav vozidla na místo a otevři editor: **Alt + C**. / Park the vehicles where they belong and open the editor:
   **Alt + C**.
2. **T** → klik na vozidlo → *Přidat vozidlo s trasou*. **M** přepne na pohled shora, kde trasu naklikáš; nebo ji ve hře
   projeď sám s **Alt + V**. / **T** → click the vehicle → *Add vehicle with a route*. **M** switches to the top view where
   you click the route; or drive it yourself in the game with **Alt + V**.
3. Na řádku vozidla přidej akce (**+ Akce**), na řádku kamery kameru (**+ Kamera**): volný let s K-framy, nebo režim kolem
   cíle (orbit, dronie, sledování…). / Add actions on the vehicle row (**+ Action**) and a camera on the camera row
   (**+ Camera**): free flight with keyframes, or a mode around a target (orbit, dronie, follow…).
4. **Enter** přehraje záběr od začátku čistě, bez HUD, a scénu předtím vrátí na start; **mezerník** přehraje od ukazatele.
   **F1** ukáže všechny zkratky. / **Enter** plays the shot from the start, clean and without HUD, after resetting the
   scene; **Space** plays from the playhead. **F1** shows all shortcuts.

## Instalace / Installation

Zip `FS25_CinemaStudio.zip` patří do složky módů hry. Editor se otevře klávesami Alt + C, nahrávání jízdy nebo chůze Alt + V,
v editoru F1 ukáže všechny zkratky. Jen pro hru jednoho hráče.

Put `FS25_CinemaStudio.zip` into the game's mods folder. Open the editor with Alt + C, record a drive or a walk with Alt + V,
press F1 in the editor for all shortcuts. Single player only.

## Rozšíření / Extensions

Mod nic dalšího nepotřebuje. S nainstalovaným [Courseplay](https://github.com/Courseplay/Courseplay_FS25) umí akce
spustit a zastavit jeho práci a položit řádky na poli podle kurzu; se [Spray Drone](https://github.com/sapavlisna/FS25-SprayDrone) ovládá drony, pumpu, hadici
a kanystry.

The mod needs nothing else. With [Courseplay](https://github.com/Courseplay/Courseplay_FS25) installed, actions can
start and stop its work and lay windrows following its course; with [Spray Drone](https://github.com/sapavlisna/FS25-SprayDrone) it controls drones, the pump, the hose
and the canisters.

## Verze / Versions

Změny po verzích jsou v `CHANGELOG.md`. / Changes per version are in `CHANGELOG.md`.

## Licence / License

Mod je pod licencí [Creative Commons BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/), plné znění je
v souboru `LICENSE`: smíš ho upravovat a šířit dál s uvedením autora (sapavlisna), ne komerčně a pod stejnou licencí.

The mod is licensed under [Creative Commons BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/), see
`LICENSE`: you may adapt and share it with attribution (sapavlisna), non-commercially and under the same license.
