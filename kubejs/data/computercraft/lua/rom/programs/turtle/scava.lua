-- scava: cava rettangolare per turtle (CC: Tweaked), con ripresa dopo i riavvii.
--
--   scava <avanti> <destra> [livelli]   nuovo lavoro
--   scava                               riprende il lavoro interrotto
--
-- La turtle parte da un angolo: scava <avanti> blocchi davanti a sé, <destra>
-- blocchi alla sua destra e scende di [livelli] (senza numero: fino alla bedrock).
-- Il livello di partenza è il primo scavato. Dietro la turtle va messa una cassa:
-- ci torna a scaricare quando è piena e a fine lavoro.
-- Carburante: lo prende da ciò che scava (carbone ecc.); se non basta torna
-- alla partenza e aspetta che glielo si metta nell'inventario.
--
-- Riavvii: posizione e avanzamento stanno nel file `.scava`, riscritto prima di
-- ogni mossa. Alla riaccensione (riavvio del server, chunk ricaricato) il file
-- `startup.lua` creato dal programma lo rilancia e il lavoro riprende.
--
-- Nota: i testi a schermo sono senza accenti perché il terminale non li mostra.

-- Blocchi da buttare quando l'inventario è pieno (svuota la lista per tenere tutto).
local SCARTI = {
  ["minecraft:cobblestone"] = true,
  ["minecraft:cobbled_deepslate"] = true,
  ["minecraft:dirt"] = true,
  ["minecraft:gravel"] = true,
  ["minecraft:tuff"] = true,
  ["minecraft:andesite"] = true,
  ["minecraft:diorite"] = true,
  ["minecraft:granite"] = true,
  ["minecraft:netherrack"] = true,
}
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
  local lung, larg, prof = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  if not lung or not larg or lung < 1 or larg < 1 or (args[3] and (not prof or prof < 1)) then
    print("Uso: scava <avanti> <destra> [livelli]")
    return
  end
  st = { lung = lung, larg = larg, prof = prof, x = 0, y = 0, z = 0, dir = 0,
         cima = 0, passo = 1, inverso = false, fondo = false, fine = false }
  if not (peripheral.hasType and peripheral.hasType("back", "inventory")) then
    print("Attenzione: nessuna cassa dietro di me, gli oggetti finiranno per terra.")
  end
end
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

local function scarica()
  gira(2)
  for s = 1, 16 do
    turtle.select(s)
    while turtle.getItemCount(s) > 0 do
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
  scarica()
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
    if st.y > 0 and turtle.detectUp() and not turtle.digUp() then
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

local function lavora()
  local limite = st.prof or math.huge
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
    else
      return "Trovato un blocco che non si rompe (bedrock?): mi fermo."
    end
  end
  return "Cava completata."
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
