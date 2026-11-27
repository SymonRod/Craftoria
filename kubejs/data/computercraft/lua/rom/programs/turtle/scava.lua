-- scava: cava rettangolare per turtle (CC: Tweaked), con ripresa dopo i riavvii.
--
--   scava <avanti> <destra> [livelli]   nuovo lavoro
--   scava <avanti> <destra> [livelli] fondo
--                                       come sopra, ma su una cava già
--                                       iniziata: scende nell'angolo di
--                                       partenza fino al punto più basso
--                                       già scavato e riparte da lì
--   scava                               riprende il lavoro interrotto
--
-- La turtle parte da un angolo: scava <avanti> blocchi davanti a sé, <destra>
-- blocchi alla sua destra e scende di [livelli] (senza numero: fino alla bedrock).
-- Il livello di partenza è il primo scavato. Dietro la turtle va messa una cassa:
-- ci torna a scaricare quando è piena e a fine lavoro.
-- Carburante: lo prende da ciò che scava (carbone ecc.) e ne tiene sempre una
-- pila di scorta quando scarica; se non basta torna alla partenza e aspetta
-- che glielo si metta nell'inventario.
--
-- Scarti: prima di partire mostra i blocchi che butterà quando l'inventario è
-- pieno e si possono togliere o aggiungere (vedi chiediScarti).
--
-- Riavvii: posizione e avanzamento stanno nel file `.scava`, riscritto prima di
-- ogni mossa. Alla riaccensione (riavvio del server, chunk ricaricato) il file
-- `startup.lua` creato dal programma lo rilancia e il lavoro riprende.
--
-- Blocchi che non si rompono: se non è bedrock o un claim di FTB Chunks riprova
-- qualche volta prima di chiudere il lavoro, e a schermo scrive il motivo.
--
-- Nota: i testi a schermo sono senza accenti perché il terminale non li mostra.

-- Blocchi da buttare quando l'inventario è pieno: lista proposta la prima volta.
-- All'avvio di un lavoro nuovo si può cambiare; l'ultima lista scelta resta nel
-- file `.scarti` della turtle e diventa la proposta successiva (vale anche per
-- scava e miniera insieme).
local SCARTI_BASE = {
  "minecraft:cobblestone",
  "minecraft:cobbled_deepslate",
  "minecraft:dirt",
  "minecraft:gravel",
  "minecraft:tuff",
  "minecraft:andesite",
  "minecraft:diorite",
  "minecraft:granite",
  "minecraft:netherrack",
}
local FILE_SCARTI = ".scarti"
local SCARTI = {} -- nome -> true, riempito da impostaScarti
local RISERVA = 20       -- carburante tenuto da parte oltre a quello per tornare
local SLOT_LIBERI = 4    -- sotto questo numero di slot vuoti va a scaricare
local STATO = ".scava"
local AVVIO = "startup.lua"
local FIRMA = "-- scava: ripresa automatica"

if not turtle then
  print("Questo programma funziona solo su una turtle.")
  return
end

-- Stato del lavoro, salvato su file.
--   x = destra, z = avanti, y = livelli scesi, rispetto alla partenza
--   dir: 0 avanti, 1 destra, 2 indietro, 3 sinistra
--   cima = primo livello ancora da scavare, passo = cella corrente della fetta
local st

local function salva(mossa)
  st.mossa, st.fuel = mossa, turtle.getFuelLevel()
  local f = fs.open(STATO .. ".tmp", "w")
  f.write(textutils.serialize(st))
  f.close()
  fs.delete(STATO)
  fs.move(STATO .. ".tmp", STATO)
end

local function carica()
  for _, nome in ipairs({ STATO, STATO .. ".tmp" }) do
    if fs.exists(nome) then
      local f = fs.open(nome, "r")
      local dati = textutils.unserialize(f.readAll() or "")
      f.close()
      if type(dati) == "table" then return dati end
    end
  end
end

-- Una schermata: titolo, spiegazione, eventuale errore e la riga dove
-- scrivere. Restituisce ciò che è stato scritto.
local function schermata(titolo, righe, errore)
  term.clear()
  term.setCursorPos(1, 1)
  local colori = term.isColor and term.isColor()
  if colori then term.setTextColor(colors.yellow) end
  print("SCAVA - " .. titolo)
  if colori then term.setTextColor(colors.white) end
  print(string.rep("-", (term.getSize())))
  for _, riga in ipairs(righe) do print(riga) end
  if errore then
    if colori then term.setTextColor(colors.red) end
    print("! " .. errore)
    if colori then term.setTextColor(colors.white) end
  end
  write("> ")
  return read() or ""
end

-- Scarti --------------------------------------------------------------------

local function impostaScarti(lista)
  SCARTI = {}
  for _, nome in ipairs(lista) do SCARTI[nome] = true end
end

local function breve(nome)
  return (nome:gsub("^minecraft:", ""))
end

-- Ultima lista scelta su questa turtle, o quella di partenza.
local function scartiSalvati()
  if fs.exists(FILE_SCARTI) then
    local f = fs.open(FILE_SCARTI, "r")
    local dati = textutils.unserialize(f.readAll() or "")
    f.close()
    if type(dati) == "table" then return dati end
  end
  return { table.unpack(SCARTI_BASE) }
end

-- Lista numerata su colonne, quante ne servono per stare in `alte` righe;
-- i nomi troppo lunghi per lo schermo vengono accorciati.
local function righeScarti(lista, alte)
  if #lista == 0 then return { "(nessuno: tengo tutto)" } end
  local w = term.getSize()
  local colonne = math.ceil(#lista / alte)
  local nrighe = math.ceil(#lista / colonne)
  local voci, largo, totale = {}, {}, 2 * (colonne - 1)
  for i, nome in ipairs(lista) do
    local c = math.floor((i - 1) / nrighe) + 1
    voci[i] = ("%2d %s"):format(i, breve(nome))
    largo[c] = math.max(largo[c] or 0, #voci[i])
  end
  for c = 1, colonne do totale = totale + largo[c] end
  while totale >= w do -- accorcia la colonna più larga finché la riga sta
    local c = 1
    for k = 2, colonne do if largo[k] > largo[c] then c = k end end
    largo[c], totale = largo[c] - 1, totale - 1
  end
  local righe = {}
  for r = 1, nrighe do
    local riga = ""
    for c = 1, colonne do
      local i = (c - 1) * nrighe + r
      if voci[i] then
        local voce = voci[i]:sub(1, largo[c])
        riga = riga .. voce .. (" "):rep(largo[c] - #voce + 2)
      end
    end
    righe[#righe + 1] = (riga:gsub("%s+$", ""))
  end
  return righe
end

-- Applica una risposta tipo "-3 5 +calcite". Restituisce la lista nuova, o
-- nil e l'errore; nessuna modifica se una parola è sbagliata.
local function modificaScarti(lista, risposta)
  local togli, metti = {}, {}
  for parola in risposta:lower():gmatch("%S+") do
    local segno, resto = parola:match("^([+-]?)(.*)$")
    if segno == "+" then
      if resto == "base" then
        for _, nome in ipairs(SCARTI_BASE) do metti[#metti + 1] = nome end
      else
        local nome = resto:find(":") and resto or "minecraft:" .. resto
        if not nome:match("^[%w_%.%-]+:[%w_%./%-]+$") then
          return nil, "nome non valido: " .. resto
        end
        metti[#metti + 1] = nome
      end
    elseif resto == "tutti" then
      for _, nome in ipairs(lista) do togli[nome] = true end
    elseif tonumber(resto) then
      local nome = lista[tonumber(resto)]
      if not nome then return nil, "il numero " .. resto .. " non c'e'" end
      togli[nome] = true
    elseif segno == "-" then
      local trovato
      for _, nome in ipairs(lista) do
        if nome == resto or breve(nome) == resto then trovato = nome end
      end
      if not trovato then return nil, resto .. " non e' nella lista" end
      togli[trovato] = true
    else
      return nil, "scrivi +" .. resto .. " o -" .. resto
    end
  end
  -- Prima toglie, poi aggiunge: "-tutti +base" riporta alla lista iniziale.
  local nuova, visti = {}, {}
  for _, nome in ipairs(lista) do
    if not togli[nome] then nuova[#nuova + 1], visti[nome] = nome, true end
  end
  for _, nome in ipairs(metti) do
    if not visti[nome] then nuova[#nuova + 1], visti[nome] = nome, true end
  end
  return nuova
end

-- Schermata degli scarti: si modifica la lista finché non si preme Invio.
-- La scelta viene salvata come proposta per il prossimo lavoro.
local function chiediScarti(titolo)
  local lista, errore = scartiSalvati(), nil
  while true do
    table.sort(lista, function(a, b) return breve(a) < breve(b) end)
    local _, h = term.getSize()
    local righe = righeScarti(lista, h - 7)
    righe[#righe + 1] = "Invio = va bene     -3 5 = togli"
    righe[#righe + 1] = "+calcite = aggiungi (id del blocco)"
    righe[#righe + 1] = "-tutti = svuota   +base = iniziale"
    local risposta = schermata(titolo, righe, errore)
    if risposta:match("^%s*$") then break end
    local nuova, e = modificaScarti(lista, risposta)
    lista, errore = nuova or lista, e
  end
  local f = fs.open(FILE_SCARTI, "w")
  f.write(textutils.serialize(lista))
  f.close()
  return lista
end

local args = { ... }
if #args == 0 then
  st = carica()
  if not st then
    print("Uso: scava <avanti> <destra> [livelli]")
    print("Esempio: scava 8 8      (fino alla bedrock)")
    print("         scava 16 16 30 (30 livelli)")
    return
  end
  -- Lo stato viene scritto prima di ogni mossa: se da allora il carburante è
  -- sceso di uno, la mossa in sospeso era stata fatta.
  if st.mossa then
    local ora = turtle.getFuelLevel()
    if ora ~= "unlimited" and ora == st.fuel - 1 then
      if st.mossa == "avanti" then
        st.x = st.x + ({ [0] = 0, 1, 0, -1 })[st.dir]
        st.z = st.z + ({ [0] = 1, 0, -1, 0 })[st.dir]
      elseif st.mossa == "su" then
        st.y = st.y - 1
      else
        st.y = st.y + 1
      end
    elseif ora ~= st.fuel then
      print("Attenzione: carburante diverso dal previsto, la posizione potrebbe essere sbagliata di un blocco.")
    end
  end
  print("Riprendo il lavoro interrotto.")
else
  local cerca = args[#args] == "fondo"
  if cerca then args[#args] = nil end
  local lung, larg, prof = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  if not lung or not larg or lung < 1 or larg < 1 or (args[3] and (not prof or prof < 1)) or #args > 3 then
    print("Uso: scava <avanti> <destra> [livelli] [fondo]")
    return
  end
  local scarti = chiediScarti("blocchi da buttare")
  term.clear()
  term.setCursorPos(1, 1)
  st = { lung = lung, larg = larg, prof = prof, x = 0, y = 0, z = 0, dir = 0,
         cima = 0, passo = 1, inverso = false, fondo = false, fine = false, scarti = scarti,
         cerca = cerca }
  if not (peripheral.hasType and peripheral.hasType("back", "inventory")) then
    print("Attenzione: nessuna cassa dietro di me, gli oggetti finiranno per terra.")
  end
end
impostaScarti(st.scarti or SCARTI_BASE)
salva()

-- Avvio automatico alla riaccensione, senza toccare uno startup già presente.
local function avvioNostro()
  if not fs.exists(AVVIO) then return false end
  local f = fs.open(AVVIO, "r")
  local prima = f.readLine()
  f.close()
  return prima == FIRMA
end

if not fs.exists(AVVIO) and not fs.exists("startup") then
  local f = fs.open(AVVIO, "w")
  f.write(FIRMA .. "\nshell.run(\"/" .. shell.getRunningProgram() .. "\")\n")
  f.close()
elseif not avvioNostro() then
  print("C'e' gia' un file di avvio: dopo un riavvio lancia 'scava' a mano.")
end

local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = 1, 0, -1, 0 }

local function gira(d)
  local diff = (d - st.dir) % 4
  if diff == 0 then return end
  if diff == 1 then
    turtle.turnRight()
  elseif diff == 2 then
    turtle.turnRight()
    st.dir = (st.dir + 1) % 4
    salva()
    turtle.turnRight()
  else
    turtle.turnLeft()
  end
  st.dir = d
  salva()
end

-- Si muove di un blocco scavando ciò che trova. Riprova per ghiaia che cade e
-- mob in mezzo; restituisce false se il blocco non si può rompere e lascia il
-- motivo in `motivo`.
local motivo
local function spingi(nome, muovi, scava, rileva, attacca)
  salva(nome)
  motivo = "bloccata da qualcosa che non va via (mob, ghiaia?)"
  for _ = 1, 60 do
    if muovi() then return true end
    if rileva() then
      local ok, perche = scava()
      if not ok then
        motivo = perche or "blocco che non si rompe"
        break
      end
    else
      attacca()
      sleep(0.2)
    end
  end
  salva()
  return false
end

local function avanti()
  if not spingi("avanti", turtle.forward, turtle.dig, turtle.detect, turtle.attack) then return false end
  st.x, st.z = st.x + DX[st.dir], st.z + DZ[st.dir]
  return true
end

local function su()
  if not spingi("su", turtle.up, turtle.digUp, turtle.detectUp, turtle.attackUp) then return false end
  st.y = st.y - 1
  return true
end

local function giu()
  if not spingi("giu", turtle.down, turtle.digDown, turtle.detectDown, turtle.attackDown) then return false end
  st.y = st.y + 1
  return true
end

-- Va a (tx, ty, tz). Salendo si muove prima in verticale, scendendo prima in
-- orizzontale: così resta sempre dentro il volume della cava.
local function vai(tx, ty, tz)
  local function verticale()
    while st.y > ty do if not su() then return false end end
    while st.y < ty do if not giu() then return false end end
    return true
  end
  local function orizzontale()
    if st.x ~= tx then
      gira(tx > st.x and 1 or 3)
      while st.x ~= tx do if not avanti() then return false end end
    end
    if st.z ~= tz then
      gira(tz > st.z and 0 or 2)
      while st.z ~= tz do if not avanti() then return false end end
    end
    return true
  end
  if ty < st.y then return verticale() and orizzontale() end
  return orizzontale() and verticale()
end

-- Brucia oggetti dell'inventario finché il carburante arriva a `obiettivo`.
local function carburante(obiettivo)
  if turtle.getFuelLevel() == "unlimited" then return true end
  obiettivo = math.min(obiettivo, turtle.getFuelLimit())
  if turtle.getFuelLevel() >= obiettivo then return true end
  salva() -- chiude la mossa in sospeso prima che il carburante cambi
  for s = 1, 16 do
    if turtle.getFuelLevel() >= obiettivo then break end
    if turtle.getItemCount(s) > 0 then
      turtle.select(s)
      while turtle.getFuelLevel() < obiettivo and turtle.refuel(1) do salva() end
    end
  end
  turtle.select(1)
  return turtle.getFuelLevel() >= obiettivo
end

local function pieno()
  local liberi = 0
  for s = 1, 16 do
    if turtle.getItemCount(s) == 0 then liberi = liberi + 1 end
  end
  return liberi < SLOT_LIBERI
end

local function buttaScarti()
  for s = 1, 16 do
    local oggetto = turtle.getItemDetail(s)
    if oggetto and SCARTI[oggetto.name] then
      turtle.select(s)
      turtle.dropDown()
    end
  end
  turtle.select(1)
end

-- Slot con la scorta di carburante da non scaricare: carbone se c'è,
-- altrimenti il primo oggetto che brucia.
local function slotScorta()
  local altro
  for s = 1, 16 do
    local oggetto = turtle.getItemDetail(s)
    if oggetto then
      turtle.select(s)
      if turtle.refuel(0) then
        if oggetto.name:find("coal") then return s end
        altro = altro or s
      end
    end
  end
  return altro
end

-- Svuota l'inventario nella cassa; con `tieniScorta` conserva una pila di
-- carburante per il resto del lavoro.
local function scarica(tieniScorta)
  gira(2)
  local scorta = tieniScorta and turtle.getFuelLevel() ~= "unlimited" and slotScorta()
  for s = 1, 16 do
    turtle.select(s)
    while s ~= scorta and turtle.getItemCount(s) > 0 do
      if not turtle.drop() then
        print("Cassa piena: svuotala, riprovo tra poco.")
        sleep(5)
      end
    end
  end
  turtle.select(1)
end

-- Torna alla partenza, scarica e fa il pieno; `serve` è il carburante per
-- andare alla prossima cella e tornare.
local function casa(motivo, serve)
  print(motivo)
  if not vai(0, 0, 0) then error("Bloccata mentre tornavo alla partenza.", 0) end
  carburante(serve) -- prima di scaricare, usa il carbone appena scavato
  scarica(true)
  while not carburante(serve) do
    print("Serve carburante: mettilo nel mio inventario.")
    os.pullEvent("turtle_inventory")
  end
  print("Riprendo.")
end

local function controlli(distanza)
  local serve = 2 * distanza + 200
  if pieno() then
    buttaScarti()
    if pieno() then casa("Inventario pieno, vado a scaricare.", serve) end
  end
  local livello = turtle.getFuelLevel()
  local ritorno = st.x + st.y + st.z + RISERVA
  if livello ~= "unlimited" and livello < ritorno and not carburante(ritorno + 100) then
    casa("Poco carburante, torno alla partenza.", serve)
  end
end

-- Percorso a serpentina sulla pianta della cava.
local celle = {}
for cx = 0, st.larg - 1 do
  for i = 0, st.lung - 1 do
    celle[#celle + 1] = { cx, cx % 2 == 0 and i or st.lung - 1 - i }
  end
end

-- Una fetta: la turtle percorre il livello `centro` e rompe anche il blocco
-- sopra e quello sotto. Restituisce false se trova un blocco che non si rompe.
local function fetta(centro, sotto)
  local function cella(n) return celle[st.inverso and #celle + 1 - n or n] end
  while st.passo <= #celle do
    local c = cella(st.passo)
    controlli(c[1] + centro + c[2])
    if not vai(c[1], centro, c[2]) then return false end
    -- Sotto la partenza tutto ciò che sta sopra fa parte della cava.
    local ok, perche = true, nil
    if st.y > 0 and turtle.detectUp() then ok, perche = turtle.digUp() end
    if not ok then
      motivo = perche or "blocco che non si rompe"
      -- Bedrock sopra la testa: torna alla cella prima, da dove si può risalire.
      if st.passo > 1 then
        local p = cella(st.passo - 1)
        vai(p[1], centro, p[2])
      end
      return false
    end
    if sotto then turtle.digDown() end
    st.passo = st.passo + 1
  end
  return true
end

-- Motivi per cui riprovare non serve, con la spiegazione da mostrare.
local DEFINITIVI = {
  ["Cannot break unbreakable block"] = "blocco che non si rompe (bedrock?)",
  ["Cannot break protected block"] = "blocco protetto da un claim (FTB Chunks): "
    .. "il proprietario del claim deve darmi il permesso",
}

local function lavora()
  local limite = st.prof or math.huge
  local tentativi = 0
  while st.fondo or st.cima < limite do
    local centro = st.fondo and st.cima or math.min(st.cima + 1, limite - 1)
    local sotto = st.fondo or centro < limite - 1
    local c = celle[st.inverso and #celle or 1]
    if fetta(centro, sotto) then
      if st.fondo then return "Arrivata alla bedrock." end
      st.cima, st.passo, st.inverso = centro + (sotto and 2 or 1), 1, not st.inverso
      salva()
      print("Scavato fino al livello " .. st.cima .. ".")
    elseif st.passo == 1 and not st.fondo and st.x == c[1] and st.z == c[2]
        and st.y < centro and st.y >= st.cima - 1 then
      -- Bedrock scendendo alla fetta nuova: ultima passata al livello raggiunto.
      st.fondo, st.cima = true, st.y
      salva()
    elseif not DEFINITIVI[motivo] and tentativi < 5 then
      -- Non è bedrock: può essere una cosa passeggera, riprova.
      tentativi = tentativi + 1
      print("Non riesco ad andare avanti: " .. tostring(motivo) .. ". Riprovo tra 10 secondi.")
      sleep(10)
    else
      return "Mi fermo, non riesco ad andare avanti: " .. (DEFINITIVI[motivo] or tostring(motivo)) .. "."
    end
  end
  return "Cava completata."
end

-- Cava già iniziata: scende nell'angolo di partenza finché trova aria (o
-- acqua) e rifà la fetta che finisce all'ultimo livello raggiunto, che
-- potrebbe essere stata lasciata a metà.
if st.cerca then
  print("Scendo fino al punto piu' basso gia' scavato.")
  local limite = st.prof or math.huge
  while st.y < limite - 1 and not turtle.detectDown() do
    controlli(st.y + 1)
    if not giu() then break end
  end
  st.cima, st.passo, st.inverso, st.cerca = math.max(st.y - 2, 0), 1, false, nil
  salva()
  print("Riparto dal livello " .. st.cima .. ".")
end

if not st.fine then
  print(lavora())
  st.fine = true
  salva()
end
if not vai(0, 0, 0) then error("Bloccata mentre tornavo alla partenza.", 0) end
scarica()
gira(0)
fs.delete(STATO)
if avvioNostro() then fs.delete(AVVIO) end
print("Sono tornata alla partenza: lavoro finito.")
