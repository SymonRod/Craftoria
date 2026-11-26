-- miniera: strip mining per turtle (CC: Tweaked), con ripresa dopo i riavvii.
--
--   miniera                              setup guidato: fa le domande una alla
--                                        volta; se c'è un lavoro interrotto
--                                        lo riprende
--   miniera <rami> <lunghezza> [Y ...]   nuovo lavoro senza le domande sui rami
--
-- La turtle scende con un pozzo verticale fino alla quota Y indicata (senza
-- numero: -58, quella dei diamanti). Laggiù scava un corridoio davanti a sé e,
-- ogni 4 blocchi, un ramo a destra e uno a sinistra lunghi <lunghezza> blocchi;
-- <rami> è il numero di coppie. Con più quote (es. 40 20 0 -30 -58) rifà la
-- stessa miniera a ogni livello, dal più alto al più basso.
-- I tunnel sono alti e larghi un blocco: a ogni passo la turtle guarda i sei
-- blocchi che ha intorno e, se vede un minerale, segue tutta la vena e poi
-- torna nel tunnel.
--
-- Alla partenza chiede le coordinate della turtle e la direzione in cui
-- guarda, poi mostra i chunk che attraverserà (nord in alto, come sulla
-- mappa): sono quelli da tenere caricati. La turtle non esce mai da lì,
-- nemmeno seguendo una vena.
--
-- Come ultima domanda mostra i blocchi che butterà quando l'inventario è
-- pieno: si possono togliere o aggiungere (vedi chiediScarti).
--
-- Dietro la turtle, alla partenza, va messa una cassa: ci torna a scaricare
-- quando è piena e a fine lavoro.
-- Carburante: lo prende da ciò che scava (carbone ecc.) e ne tiene sempre una
-- pila di scorta quando scarica; se non basta torna alla partenza e aspetta
-- che glielo si metta nell'inventario.
--
-- Riavvii: posizione e avanzamento stanno nel file `.miniera`, riscritto prima
-- di ogni mossa. Alla riaccensione (riavvio del server, chunk ricaricato) il
-- file `startup.lua` creato dal programma lo rilancia e il lavoro riprende.
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
-- Blocchi da seguire come i minerali anche se non hanno il tag "ores".
local EXTRA = {
  ["minecraft:ancient_debris"] = true,
}
local PASSO = 4          -- distanza tra un ramo e il successivo (3 blocchi pieni in mezzo)
local MAX_VENA = 64      -- blocchi al massimo per una vena, poi torna nel tunnel
local RISERVA = 150      -- carburante tenuto da parte oltre a quello per tornare
local SLOT_LIBERI = 4    -- sotto questo numero di slot vuoti va a scaricare
local STATO = ".miniera"
local AVVIO = "startup.lua"
local FIRMA = "-- miniera: ripresa automatica"

if not turtle then
  print("Questo programma funziona solo su una turtle.")
  return
end

-- Stato del lavoro, salvato su file.
--   x = destra, z = avanti, y = livelli scesi, rispetto alla partenza
--   dir: 0 avanti, 1 destra, 2 indietro, 3 sinistra
--   livelli = livelli da scavare (blocchi sotto la partenza), nliv = quello corrente
--   liv = livello a cui si sta lavorando (nil finché il pozzo non ci arriva)
--   ox, oy, oz, verso = posizione e direzione della partenza nel mondo
--   area = blocchi del mondo da cui non uscire: x min, x max, z min, z max
--   ramo = ramo corrente (da 0), fase: 0 corridoio, 1 ramo destro, 2 sinistro
--   avanz = blocchi già scavati del tratto corrente
--   pila = mosse fatte dentro una vena a partire dal tunnel (0-3, 4 su, 5 giù)
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

local function uso()
  print("Uso: miniera   (setup guidato)")
  print("     miniera <rami> <lunghezza> [Y ...]")
  print("Esempio: miniera 6 24        (a Y -58)")
  print("         miniera 6 24 -20    (a Y -20)")
  print("         miniera 8 48 40 10 -20 -58")
end

-- Direzioni del mondo: 0 nord (-Z), 1 est (+X), 2 sud (+Z), 3 ovest (-X).
local MONDO = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local PUNTI = { n = 0, e = 1, s = 2, o = 3, w = 3 }

-- Coordinate del mondo del punto (x, z) relativo alla partenza.
local function mondo(x, z)
  local av, dx = MONDO[st.verso], MONDO[(st.verso + 1) % 4]
  return st.ox + x * dx[1] + z * av[1], st.oz + x * dx[2] + z * av[2]
end

-- Una schermata del setup: titolo, spiegazione, eventuale errore e la riga
-- dove scrivere. Restituisce ciò che è stato scritto.
local function schermata(titolo, righe, errore)
  term.clear()
  term.setCursorPos(1, 1)
  local colori = term.isColor and term.isColor()
  if colori then term.setTextColor(colors.yellow) end
  print("MINIERA - " .. titolo)
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

-- Ripete la schermata finché `leggi(risposta)` non restituisce un valore;
-- altrimenti restituisce nil e l'errore da mostrare.
local function domanda(titolo, righe, leggi)
  local errore
  while true do
    local valore, e = leggi(schermata(titolo, righe, errore))
    if valore ~= nil then return valore end
    errore = e
  end
end

local function interi(testo)
  local n = {}
  for v in testo:gmatch("-?%d+") do n[#n + 1] = tonumber(v) end
  return n
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

local function chiediPosizione(passo)
  local n = domanda(passo, {
    "DOVE SONO?",
    "Guardami e premi F3: a destra c'e'",
    "\"Targeted Block\" con tre numeri.",
    "Scrivili qui, separati da spazi.",
    "",
    "Esempio: 120 64 -35",
  }, function(r)
    local n = interi(r)
    if #n == 3 then return n end
    return nil, "Servono tre numeri: X Y Z"
  end)
  st.ox, st.oy, st.oz = n[1], n[2], n[3]
end

local function chiediVerso(passo)
  st.verso = domanda(passo, {
    "DOVE GUARDO?",
    "Mettiti dietro di me, dal lato della",
    "cassa, e guarda nella mia direzione.",
    "In F3 leggi \"Facing: north\" (o east,",
    "south, west) e scrivi la lettera:",
    "",
    " n = nord    e = est",
    " s = sud     o = ovest",
  }, function(r)
    local v = PUNTI[r:lower():sub(1, 1)]
    if v then return v end
    return nil, "Scrivi una lettera: n, e, s oppure o"
  end)
end

local function chiediLunghezza(passo)
  return domanda(passo, {
    "QUANTO LUNGHI I RAMI?",
    "Visto dall'alto scavo cosi':",
    "  <-------+------->   ^",
    "  <-------+------->   | avanti",
    "  <-------+------->",
    "          T = io (cassa dietro)",
    "Blocchi di ogni ramo, a destra e a",
    "sinistra. Un chunk = 16 blocchi.",
    "Invio = 32",
  }, function(r)
    local n = r == "" and 32 or tonumber(r)
    if n and n >= 1 then return math.floor(n) end
    return nil, "Serve un numero, per esempio 32"
  end)
end

local function chiediRami(passo)
  return domanda(passo, {
    "QUANTI RAMI?",
    "Vado avanti con un corridoio e ogni",
    PASSO .. " blocchi faccio un ramo a destra e",
    "uno a sinistra. Quante volte?",
    "",
    " 6 = corridoio di " .. 5 * PASSO .. " blocchi",
    " 12 = corridoio di " .. 11 * PASSO .. " blocchi",
    "",
    "Invio = 6",
  }, function(r)
    local n = r == "" and 6 or tonumber(r)
    if n and n >= 1 then return math.floor(n) end
    return nil, "Serve un numero, per esempio 6"
  end)
end

local function chiediQuote(passo)
  local predefinita = math.min(-58, st.oy)
  return domanda(passo, {
    "A CHE ALTEZZA SCAVO?",
    "Io sono a Y " .. st.oy .. ". Scrivi la Y a cui",
    "fare la miniera. Con piu' numeri ne",
    "faccio una per ogni altezza, tutte",
    "uguali, una sotto l'altra.",
    "",
    "Esempio: 40 10 -58",
    "Diamanti: -58",
    "Invio = " .. predefinita,
  }, function(r)
    local quote = interi(r)
    if #quote == 0 then
      if r:find("%S") then return nil, "Servono numeri, es: 40 10 -58" end
      return { predefinita }
    end
    for _, q in ipairs(quote) do
      if q > st.oy then return nil, "Y " .. q .. " e' sopra di me (Y " .. st.oy .. ")" end
    end
    return quote
  end)
end

-- Calcola i chunk toccati dalla miniera (e li salva in st.area); restituisce
-- le righe da mostrare, con la mappa se ci sta nello schermo.
local function chunkToccati()
  -- Dalla cassa (z = -1) alla fine del corridoio, per tutta la lunghezza dei rami.
  local xa, za = mondo(-st.lung, -1)
  local xb, zb = mondo(st.lung, (st.rami - 1) * PASSO)
  local cx1, cx2 = math.floor(math.min(xa, xb) / 16), math.floor(math.max(xa, xb) / 16)
  local cz1, cz2 = math.floor(math.min(za, zb) / 16), math.floor(math.max(za, zb) / 16)
  st.area = { cx1 * 16, cx2 * 16 + 15, cz1 * 16, cz2 * 16 + 15 }
  local tx, tz = math.floor(st.ox / 16), math.floor(st.oz / 16)
  local larg, alt = cx2 - cx1 + 1, cz2 - cz1 + 1
  local righe = {
    "CHUNK DA TENERE CARICATI: " .. larg * alt,
    "X da " .. st.area[1] .. " a " .. st.area[2],
    "Z da " .. st.area[3] .. " a " .. st.area[4],
  }
  if larg <= 18 and alt <= 5 then
    righe[#righe + 1] = "Nord in alto, T = io:"
    for cz = cz1, cz2 do
      local riga = {}
      for cx = cx1, cx2 do riga[#riga + 1] = (cx == tx and cz == tz) and "T" or "#" end
      righe[#righe + 1] = "  " .. table.concat(riga, " ")
    end
  else
    righe[#righe + 1] = larg .. " chunk da ovest a est,"
    righe[#righe + 1] = alt .. " da nord a sud."
  end
  return righe
end

-- Carburante per scendere fino al punto più lontano della miniera e tornare.
local function serve()
  local liv = st.liv or st.livelli[math.min(st.nliv, #st.livelli)]
  return 2 * (liv + (st.rami - 1) * PASSO + st.lung) + RISERVA + 100
end

local args = { ... }
local ripresa = #args == 0 and carica()
if ripresa then
  st = ripresa
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
      -- La mossa era dentro una vena: aggiorna anche la strada del ritorno.
      if st.spinta then
        st.pila[#st.pila + 1] = st.spinta
      elseif st.ritiro then
        st.pila[#st.pila] = nil
      end
    elseif ora ~= st.fuel then
      print("Attenzione: carburante diverso dal previsto, la posizione potrebbe essere sbagliata di un blocco.")
    end
  end
  st.spinta, st.ritiro = nil, nil
  print("Riprendo il lavoro interrotto.")
else
  local guidato = #args == 0
  local rami, lung = tonumber(args[1]), tonumber(args[2])
  local quote = {}
  for i = 3, #args do quote[#quote + 1] = tonumber(args[i]) and math.floor(tonumber(args[i])) end
  if not guidato and (not rami or not lung or rami < 1 or lung < 1 or #quote ~= #args - math.min(#args, 2)) then
    uso()
    return
  end
  st = { livelli = {}, nliv = 1,
         x = 0, y = 0, z = 0, dir = 0, ramo = 0, fase = 0, avanz = 0, pila = {}, fine = false }
  local passi = guidato and 6 or 3
  chiediPosizione("passo 1 di " .. passi)
  chiediVerso("passo 2 di " .. passi)
  if guidato then
    lung = chiediLunghezza("passo 3 di 6")
    rami = chiediRami("passo 4 di 6")
    quote = chiediQuote("passo 5 di 6")
  elseif #quote == 0 then
    quote[1] = -58
  end
  st.scarti = chiediScarti("passo " .. passi .. " di " .. passi .. ": scarti")
  st.rami, st.lung = math.floor(rami), math.floor(lung)
  -- Dalle quote Y ai livelli da scendere, dal più alto al più basso.
  table.sort(quote, function(a, b) return a > b end)
  for _, q in ipairs(quote) do
    local giu = st.oy - q
    if giu < 0 then
      print("Y " .. q .. " e' sopra la turtle (Y " .. st.oy .. ").")
      return
    end
    if giu ~= st.livelli[#st.livelli] then st.livelli[#st.livelli + 1] = giu end
  end

  -- Riepilogo in due schermate: cosa scaverà, poi i chunk da caricare.
  table.sort(quote)
  local elenco = {}
  for i = #quote, 1, -1 do elenco[#elenco + 1] = quote[i] end
  local blocchi = #st.livelli * (st.rami * 2 * st.lung + (st.rami - 1) * PASSO)
  local righe = {
    "COSA FARO'",
    "Rami: " .. st.rami .. " a destra e " .. st.rami .. " a sinistra,",
    "lunghi " .. st.lung .. " blocchi.",
    "Corridoio: " .. (st.rami - 1) * PASSO .. " blocchi davanti a me.",
    "Altezze Y: " .. table.concat(elenco, " "),
    "In tutto " .. blocchi .. " blocchi di tunnel.",
  }
  local ho = turtle.getFuelLevel()
  if ho ~= "unlimited" then
    righe[#righe + 1] = "Carburante: ho " .. ho .. ", servono " .. serve() .. "."
    if ho < serve() then righe[#righe + 1] = "Metti carbone nel mio inventario." end
  end
  if not (peripheral.hasType and peripheral.hasType("back", "inventory")) then
    righe[#righe + 1] = "ATTENZIONE: nessuna cassa dietro!"
  end
  righe[#righe + 1] = "Invio = avanti, n = annulla"
  local function conferma(r)
    return r:lower():sub(1, 1) ~= "n"
  end
  local ok = domanda("riepilogo 1 di 2", righe, conferma)
  if ok then
    righe = chunkToccati()
    righe[#righe + 1] = "Invio = parto, n = annulla"
    ok = domanda("riepilogo 2 di 2", righe, conferma)
  end
  term.clear()
  term.setCursorPos(1, 1)
  if not ok then
    print("Annullato: non mi sono mossa.")
    return
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
  print("C'e' gia' un file di avvio: dopo un riavvio lancia 'miniera' a mano.")
end

local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = 1, 0, -1, 0 }
local OPPOSTA = { [0] = 2, 3, 0, 1, 5, 4 }

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
-- mob in mezzo; restituisce false se il blocco non si può rompere.
local function spingi(nome, muovi, scava, rileva, attacca)
  salva(nome)
  for _ = 1, 60 do
    if muovi() then return true end
    if rileva() then
      if not scava() then break end
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

-- Una mossa in una delle sei direzioni: 0-3 in orizzontale, 4 su, 5 giù.
local function muovi(d)
  if d == 4 then return su() end
  if d == 5 then return giu() end
  gira(d)
  return avanti()
end

local function vaiX(tx)
  if st.x ~= tx then
    gira(tx > st.x and 1 or 3)
    while st.x ~= tx do if not avanti() then return false end end
  end
  return true
end

local function vaiZ(tz)
  if st.z ~= tz then
    gira(tz > st.z and 0 or 2)
    while st.z ~= tz do if not avanti() then return false end end
  end
  return true
end

local function vaiY(ty)
  while st.y > ty do if not su() then return false end end
  while st.y < ty do if not giu() then return false end end
  return true
end

-- Torna alla partenza lungo i tunnel: ramo, corridoio, pozzo.
local function vaiCasa()
  if not (vaiX(0) and vaiZ(0) and vaiY(0)) then
    error("Bloccata mentre tornavo alla partenza.", 0)
  end
end

-- Va al punto (tx, tz) della miniera passando sempre dal corridoio (x = 0).
local function vaiPunto(tx, tz)
  local ok
  if st.y ~= st.liv then
    ok = vaiX(0) and vaiZ(0) and vaiY(st.liv)
  else
    ok = true
  end
  if ok and st.z ~= tz then ok = vaiX(0) and vaiZ(tz) end
  if not (ok and vaiX(tx)) then error("Bloccata dentro la miniera.", 0) end
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

local function slotLiberi()
  local liberi = 0
  for s = 1, 16 do
    if turtle.getItemCount(s) == 0 then liberi = liberi + 1 end
  end
  return liberi
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

-- Alla partenza: non si scende finché non c'è carburante per andata e ritorno.
local function rifornisci()
  while not carburante(serve()) do
    print("Serve carburante (" .. turtle.getFuelLevel() .. " su " .. serve() .. "): mettilo nel mio inventario.")
    os.pullEvent("turtle_inventory")
  end
end

local function casa(motivo)
  print(motivo)
  vaiCasa()
  carburante(serve()) -- prima di scaricare, usa il carbone appena scavato
  scarica(true)
  rifornisci()
  print("Riprendo.")
end

local function distanzaCasa()
  return math.abs(st.x) + st.y + st.z + #st.pila
end

-- Controlli fatti solo nel tunnel, mai dentro una vena.
local function controlli()
  if slotLiberi() < SLOT_LIBERI then
    buttaScarti()
    if slotLiberi() < SLOT_LIBERI then casa("Inventario pieno, vado a scaricare.") end
  end
  local livello = turtle.getFuelLevel()
  local ritorno = distanzaCasa() + RISERVA
  if livello ~= "unlimited" and livello < ritorno and not carburante(ritorno + 100) then
    casa("Poco carburante, torno alla partenza.")
  end
end

local function minerale(ok, blocco)
  if not ok then return false end
  if EXTRA[blocco.name] then return true end
  local tag = blocco.tags
  if tag and (tag["c:ores"] or tag["forge:ores"]) then return true end
  return blocco.name:find("_ore$") ~= nil
end

-- Vero se un passo in direzione `d` resta nei chunk annunciati alla partenza.
local function dentro(d)
  local x, z = mondo(st.x + DX[d], st.z + DZ[d])
  return x >= st.area[1] and x <= st.area[2] and z >= st.area[3] and z <= st.area[4]
end

-- Guarda i sei blocchi intorno; restituisce la direzione del primo minerale.
local function cerca()
  if minerale(turtle.inspectUp()) then return 4 end
  if minerale(turtle.inspectDown()) then return 5 end
  local inizio = st.dir
  for i = 0, 3 do
    gira((inizio + i) % 4)
    if minerale(turtle.inspect()) and dentro(st.dir) then return st.dir end
  end
end

-- Dentro una vena si va avanti solo se c'è posto per ciò che si scava e
-- carburante per tornare.
local function puoProseguire()
  if slotLiberi() == 0 then
    buttaScarti()
    if slotLiberi() == 0 then return false end
  end
  local livello = turtle.getFuelLevel()
  return livello == "unlimited" or livello > distanzaCasa() + 20
end

-- Scava la vena che tocca la posizione corrente e torna dov'era. Non usa
-- ricorsione: la strada fatta sta in st.pila, così dopo un riavvio basta
-- richiamarla per riprendere da dove si trova la turtle.
local function vena()
  local scavati, basta = 0, false
  while true do
    local d = not basta and scavati < MAX_VENA and puoProseguire() and cerca()
    if d then
      st.spinta = d
      if muovi(d) then
        st.pila[#st.pila + 1] = d
        scavati = scavati + 1
      else
        basta = true -- minerale che non si rompe: si torna indietro e basta
      end
      st.spinta = nil
    elseif #st.pila > 0 then
      st.ritiro = true
      if not muovi(OPPOSTA[st.pila[#st.pila]]) then
        error("Bloccata dentro una vena.", 0)
      end
      st.pila[#st.pila] = nil
      st.ritiro = nil
    else
      return
    end
  end
end

-- Scava `n` blocchi in direzione `dir` partendo da (ox, oz), cercando vene a
-- ogni passo. Restituisce false se trova un blocco che non si rompe.
local function tratto(dir, n, ox, oz)
  while st.avanz < n do
    controlli()
    vaiPunto(ox + DX[dir] * st.avanz, oz + DZ[dir] * st.avanz)
    gira(dir)
    if not avanti() then return false end
    st.avanz = st.avanz + 1
    salva()
    vena()
  end
  return true
end

-- Scende nel pozzo fino al prossimo livello. Restituisce false se non ce ne
-- sono altri da fare.
local function scendi()
  local meta = st.livelli[st.nliv]
  print("Scendo a Y " .. (st.oy - meta) .. ".")
  if not (vaiX(0) and vaiZ(0)) then error("Bloccata dentro la miniera.", 0) end
  -- Carburante per scendere fin lì e risalire tutto il pozzo.
  local livello, occorre = turtle.getFuelLevel(), 2 * meta - st.y + RISERVA
  if livello ~= "unlimited" and livello < occorre and not carburante(occorre) then
    casa("Poco carburante, torno alla partenza.")
  end
  while st.y < meta do
    if not giu() then
      -- Fermata dalla bedrock: si risale sopra lo strato dove è a macchie e
      -- questo diventa l'ultimo livello, se non è a ridosso del precedente.
      meta = math.max(st.y - 4, 0)
      for i = st.nliv, #st.livelli do st.livelli[i] = nil end
      if st.nliv > 1 and meta < st.livelli[st.nliv - 1] + 3 then
        salva()
        return false
      end
      st.livelli[st.nliv] = meta
      print("Bedrock: l'ultimo livello sara' a Y " .. (st.oy - meta) .. ".")
      break
    end
  end
  st.liv = meta
  salva()
  return true
end

-- Corridoio e rami del livello corrente.
local function livello()
  while st.ramo < st.rami do
    local zr = st.ramo * PASSO
    if st.fase == 0 then
      if st.ramo > 0 and not tratto(0, PASSO, 0, zr - PASSO) then
        print("Corridoio bloccato da un blocco che non si rompe.")
        return
      end
      st.fase, st.avanz = 1, 0
      salva()
    end
    if st.fase == 1 then
      tratto(1, st.lung, 0, zr)
      st.fase, st.avanz = 2, 0
      salva()
    end
    tratto(3, st.lung, 0, zr)
    st.ramo, st.fase, st.avanz = st.ramo + 1, 0, 0
    salva()
    print("Y " .. (st.oy - st.liv) .. ": finito il ramo " .. st.ramo .. " di " .. st.rami .. ".")
  end
end

local function lavora()
  if st.x == 0 and st.y == 0 and st.z == 0 then rifornisci() end
  -- Dopo un riavvio: finisce la vena in corso e riguarda intorno al punto
  -- del tunnel dove si era fermata.
  if st.liv and (#st.pila > 0 or st.y == st.liv) then vena() end

  while st.nliv <= #st.livelli do
    if not st.liv and not scendi() then break end
    livello()
    st.nliv, st.liv, st.ramo, st.fase, st.avanz = st.nliv + 1, nil, 0, 0, 0
    salva()
  end
  return "Miniera completata."
end

if not st.fine then
  print(lavora())
  st.fine = true
  salva()
end
vaiCasa()
scarica()
gira(0)
fs.delete(STATO)
if avvioNostro() then fs.delete(AVVIO) end
print("Sono tornata alla partenza: lavoro finito.")
