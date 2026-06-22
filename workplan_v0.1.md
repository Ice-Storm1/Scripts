# Conquest v0.1
## Piano di Sviluppo Completo
## Aggiungi Descrizione per la missione scenario (appare sotto immagine) 
---

## STRUTTURA PROGETTO SINGLEPLAYER ONLY

```
Conquest.Altis/
├── description.ext                 (respawn, CfgRemoteExec, CfgDebriefing, CfgFunctions)
├── mission.sqm                     (giocatore + setup mappa iniziale)
├── init.sqf                        (chiama setupGUI pre-partita)
├── initServer.sqf                  (server init, loop principali)
├── initPlayerLocal.sqf             (player init minimo)
│
├── functions/
│   ├── fn_setupGUI.sqf
│   ├── fn_setupFaction.sqf
│   ├── fn_setupMap.sqf
│   ├── fn_spawnPlayer.sqf
│   ├── fn_homeMenu.sqf
│   ├── fn_captureLoop.sqf
│   ├── fn_vehicleMenu.sqf
│   ├── fn_vehicleSpawn.sqf
│   ├── fn_aiAttacks.sqf
│   ├── fn_aiGarrison.sqf
│   ├── fn_aiCounterattack.sqf
│   ├── fn_aiFortify.sqf
│   ├── fn_aiBuyLogic.sqf
│   ├── fn_scoreSystem.sqf
│   ├── fn_logistics.sqf
│   ├── fn_supportStrike.sqf
│   ├── fn_supportSupply.sqf
│   ├── fn_supportReinforce.sqf
│   ├── fn_transportHeli.sqf
│   └── fn_endConditions.sqf
```

---

## MODULO 0 — PRE-GAME SETUP

Prima che la partita carichi, il giocatore vede una **schermata GUI interattiva** con:

### 0A — Scelta Fazione
- Step 1: BLUFOR (ovest) o OPFOR (est)
- Step 2: Fazione specifica (NATO / CSAT / USMC / AAF / workshop)
- Ogni fazione ha uniformi, equipaggiamento, veicoli propri

### 0B — Loadout Preset (20+ per fazione)
- Ruoli: Fante, Fante AT, Medico, Mitragliere, Cecchino, Sergente, Granatiere, Esplosivista, Pilota, Elicotterista, Carrista, Operatore Speciale
- Ogni preset include: armi, uniforme, casco, zaino, vest, accessori, munizioni
- Cambia aspetto visivo in base alla fazione scelta

### 0C — Squadra Preset
- Cambia numero e tipo degli AI follower
- Esempi: Squadra Assalto (6 fanti), Fireteam (4 + AR), Pattuglia (2), Scout (cecchino + fante)

### 0D — Setup Mappa
- Mappa interattiva (Altis o qualsiasi altra)
- Click per posizionare: **Base A**, **Base B**, **Settori** (min 3, max 10)
- Opzione: generazione **casuale** dei settori
- Slider per raggio basi e raggio settori
- **Durata partita**: 30min / 1h / 3h / 5h

### 0E — Avvio Partita
- Bottone "Inizia partita"
- Sistema carica la missione con le coordinate scelte

---

## MODULO 1 — HOME MENU (dopo morte)

Quando il giocatore muore o deve respawnare:
- **Mappa in tempo reale** con:
  - Posizione settori e loro owner (BLUFOR/OPFOR/neutro)
  - Progresso cattura settori in corso
  - Linea del fronte
- **Cambio Loadout**: seleziona nuovo preset
- **Cambio Squadra**: seleziona nuovo preset squadra
- **Pulsante "Respawn"**: spawna alla Base A con loadout/squadra scelti

---

## MODULO 2 — SPAWN E VEICOLI

### 2A — Spawn Giocatore
- Alla Base A, con loadout scelto
- AI follower della squadra scelta spawnano con te

### 2B — Menu Veicoli (alla base)
- Punto fisico alla Base A (scroll mouse → "Vehicle Spawn")
- Lista veicoli disponibili per la **fazione scelta**
- **Esclusi**: barche, aerei
- **Inclusi**: MRAP, Camion, APC, IFV, Carri, Elicotteri
- **Costo in Punti Veicolo** (sistema separato dalla logistica):

| Veicolo | Costo PV |
|---|---|
| MRAP / Jeep | 10 |
| Camion Trasporto/Munizioni | 15 |
| IFV / APC Ruotato | 25 |
| APC Cingolato | 30 |
| Elicottero Trasporto | 35 |
| Carro Leggero | 40 |
| Elicottero Armato | 45 |
| Carro Pesante | 50 |

- **Cooldown globale**: 1 minuto tra spawn
- **Punti Veicolo**: +1/min passivo, +5 bonus per cattura settore

---

## MODULO 3 — SISTEMA CATTURA (AAS)

### 3A — Loop Cattura (ogni 1s)
- Ogni settore ha una zona (cerchio col raggio scelto)
- Presenza BLUFOR nella zona → progresso aumenta
- Presenza OPFOR → progresso rallenta o cala
- Progresso 100% → settore catturato da BLUFOR

### 3B — Stati Settore
- **BASE**: settore di partenza (non catturabile, sempre tuo)
- **CAPTURED**: settore già tuo
- **CAPTURABLE**: primo settore nemico dopo i tuoi (si può catturare)
- **LOCKED**: settori nemici oltre il CAPTURABLE (non ancora catturabili)

---

## MODULO 4 — SISTEMA AI

### 4A — Guarnigione (sempre attiva)
- Ogni settore nemico ha 3-6 soldati in presidio (GUARD)
- Se < 2 vivi → rimpiazza unità

### 4B — Attacchi Pianificati (ogni 10 min)
- Dalla **Base B** spawna: 1 squadra (5-8 unità) + 1 veicolo
- Nessun aereo fisso, elicotteri sì (atterrano, scaricano truppe)

### 4C — Contrattacco
- Quando un settore viene catturato da BLUFOR:
  - Unità OPFOR entro **500m** dal settore perso → waypoint immediato MOVE + SAD
  - Se nessuna unità nel raggio → aspetta il prossimo timer 10min

### 4D — Fortificazione (dopo 1 ora)
- Se l'AI mantiene un settore per **1 ora continuativa**:
  - Sblocca **spawn fanteria** nel settore
  - Poi **spawn veicoli**
  - Poi **spawn elicotteri**
- Se riconquisti il settore, gli spawn vengono distrutti

### 4E — AI Compra Logistica (ogni 20 min)
- AI spende automaticamente i punti supporto del team OPFOR
- Priorità: difesa settori minacciati → contrattacco → rinforzi offensivi

---

## MODULO 5 — PUNTI E LOGISTICA

### 5A — Punti Supporto (condivisi team)
- **+5/min** per settore posseduto
- **+30 bonus** per cattura settore
- **Nessuna penalità** per morte

### 5B — Tabella Costi Supporto

| Item | Costo PT | Descrizione |
|---|---|---|
| Rifornimento CAS | 60 | Cassa munizioni paracadutata alla posizione del giocatore |
| Cortina Fumogena | 40 | Cortina fumogena su area selezionata |
| Drone Ricognizione | 50 | Rivela area per 60 secondi (tutti i nemici visibili) |
| Medevac | 70 | Elicottero arriva e cura tutte le unità nel raggio |
| AT Strike | 80 | Missile drone su veicolo nemico |
| Artiglieria | 100 | 6 colpi di mortaio su area |
| Trasporto Elicottero | 150 | Heli trasporta truppe A→B (destinazione su mappa) |
| CAS Strike | 150 | Bombardamento jet su posizione mirata |
| Squadra Rinforzo | 120 | 1 squadra AI amica spawna con te |
| Vehicle Drop | 200 | Veicolo blindato paracadutato |
| Eliassalto | 250 | 2 elicotteri truppe attaccano settore |
| Barrage Pesante | 300 | 12 colpi artiglieria pesante su settore |
| Plotone Corazzato | 400 | 2 carri + 1 APC avanzano verso settore |

### 5C — Acquisti
- **Nessun cooldown** (basta avere punti sufficienti)
- I punti si consumano all'acquisto
- Tutto il team vede la spesa

---

## MODULO 6 — TRASPORTO ELICOTTERO

- Attivabile dalla logistica (150 PT)
- Si apre **mappa interattiva** → clicchi destinazione
- Elicottero spawna e carica truppe (player + AI)
- Vola a destinazione e atterra
- Scarica truppe e decolla (o resta disponibile)
- Utilizzabile sia da **player** che da **AI**

---

## MODULO 7 — VITTORIA / FINE PARTITA

### 7A — Condizioni
1. **Occupare TUTTI i settori** → VITTORIA
2. **Timer scaduto** (30min/1h/3h/5h) → vince **chi ha più settori**
3. **Parità settori** → PAREGGIO

### 7B — Debriefing
- Schermata riepilogativa con:
  - Settori catturati
  - Kills player
  - Punti guadagnati (supporto + veicolo)
  - Veicoli distrutti
  - Tempo giocato
  - Esito partita (Win/Lose/Draw)

---

## MODULO 8 — SUPPORTO MULTI-MAPPA

- Il sistema funziona su **qualsiasi mappa**
- Setup GUI e posizionamento settori si adattano alla mappa caricata
- Mappa selezionabile dal giocatore all'inizio

---

## BUILD E DEPLOY

solo HEMTT niente armake, o altra roba

