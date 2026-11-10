# Changelog

Verze odpovídá `<version>` v `modDesc.xml`. Vydání bere poznámky z oddílu své verze, takže nová verze musí mít oddíl
dřív, než se vydá.

The version matches `<version>` in `modDesc.xml`. A release takes its notes from the section of its version.

## 0.5.3.0 (beta)

- Pole lze nastavit jen částečně: menu pole → Zóny sklizně. Sklizeno podle kurzu Courseplay až do bodu, kam kombajn dojel (klik
  na kurz nebo poloha kombajnu), a obdélníky sklizeno / nesklizeno ze tří kliknutí. Reset vrátí pole do stejného stavu, sláma
  se sype jen na projeté řádky. / A field can be set only partly: field menu → Harvest zones. Harvested along the Courseplay
  course up to where the combine got to (click on the course or the combine's position) and harvested / standing rectangles
  from three clicks. Reset restores the same state; straw is dropped only on the rows already driven.

## 0.5.2.0 (beta)

- Nahrávání zachytí, co hráč zapojí nebo zapne na strojích kolem (hadice a motor pumpy SprayDrone): po importu jsou to akce
  objektu i se stavem ze startu záznamu. / Recording captures what the player connects or switches on nearby machines
  (SprayDrone hoses and pump engine): after import they become object actions, including the state at the start.
- Předmět na vozidle (big bag na vleku, paleta nebo pumpa na korbě, balíky na návěsu) s ním jede, reset ho vrátí na vozidlo.
  / An item lying on a vehicle (big bag on a trailer, pallet or pump on a pickup bed, bales) rides along with it, and reset
  puts it back on the vehicle.
- Předmět mapy (kýbl, bedna), který postava odnesla, se při resetu vrátí, odkud ho vzala, i po novém spuštění hry.
  / A map object (bucket, crate) carried away returns to where it was picked up on reset, even after restarting the game.

## 0.5.1.1 (beta)

- Průvodce má snímky přímo z hry (editor, časová osa, menu bloku, vozidla, akcí a prostředí, panel Přidat, pohled shora,
  křivky). / The guide now has screenshots taken in the game (editor, timeline, block, vehicle, action and environment
  menus, Add panel, top-down view, curves).

## 0.5.1.0 (beta)

- Opravy z testu všech menu, kamer a akcí. / Fixes from a test of all menus, cameras and actions.
  - Světla zapřažených vleků se po přehrání vrátí na výchozí stav (dřív zůstala svítit).
    Lights of attached trailers return to their start state after playback (they used to stay on).
  - Kamera vozidla venku (Připevnit → Kamera vozidla) míří na vozidlo, dřív ukazovala místo, kde kamera naposledy byla.
    The outside vehicle camera mount points at the vehicle; it used to show wherever the camera was last.
  - Průjezd: čas průjezdu už nezůstane za koncem bloku po jeho zkrácení.
    Pass: the pass-by time no longer ends up past the end of a shortened block.
  - Neplatný obsah nádrže ve stavu záběru se zapíše do logu, ručně psané záběry bez úhlu nepadají.
    An invalid tank content in a shot state is logged, and hand-written shots without an angle no longer crash.
- Nahrávání pěšky (Alt + V mimo vozidlo): trasa s tempem, zastávky s natočením, skoky a zvednuté předměty i s tím, jak
  je postava drží a natáčí; předměty se na začátku záběru vrátí, kde ležely.
  Recording on foot (Alt + V outside a vehicle): route with pace, stops with facing, jumps and picked-up items including
  how they are held and turned; the items return to where they lay at the start of the shot.
- Nová akce postavy Skočit. / New character action Jump.

## 0.5.0.0 (beta)

První veřejná verze. / First public version.

- Kamera po K-framech a 17 režimů kolem cíle (orbit, dronie, rocket, helix, sledování, průjezd…), ohnisko 14–400 mm,
  křivky rychlosti, širokoúhlé pruhy, mřížka třetin, třes z ruky.
  Keyframed camera and 17 modes around a target, 14–400 mm lens, speed curves, letterbox, rule of thirds, handheld shake.
- Vozidla a postavy jako herci s naklikanou nebo nahranou trasou (Alt + V) a akcemi v přesném čase.
  Vehicles and characters as actors on clicked or recorded routes (Alt + V) with timed actions.
- Každé přehrání vrátí scénu: vozidla, náklad, palety, balíky, hromady, čas, počasí a volitelně pole včetně řádků.
  Every playback resets the scene: vehicles, loads, pallets, bales, heaps, time, weather and optionally fields with windrows.
- Volitelná rozšíření pro Courseplay a Spray Drone. / Optional extensions for Courseplay and Spray Drone.
- Průvodce česky a anglicky ve složce `manual`. / Czech and English guide in the `manual` folder.
- Jen pro hru jednoho hráče. / Single player only.
