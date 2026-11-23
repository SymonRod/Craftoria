// Craftoria Amici: bilanciamento di Mystical Agriculture.
//
// Le essenze di METALLI e GEMME non si trasformano più in lingotti/gemme al banco da lavoro:
// vanno raffinate nelle macchine del pack, con resa che cresce col livello tecnologico.
// Le altre essenze (legno, terra, mob, colture, redstone, glowstone, ecc.) restano invariate.
//
// Livelli (resa = moltiplicatore della ricetta originale essenza -> lingotto/gemma di MA):
//   Create Crushing Wheels           x0.50  metalli: essenza -> crushed raw ore (poi washing/fornace)
//                                           se non esiste il crushed ore: pepite; gemme: gemma diretta
//   MI Macerator (steam age)         x0.75  metalli: essenza -> polvere (poi fornace); gemme: gemma diretta
//   Mekanism Purification (+ossigeno) x1.25 metalli con filiera: essenza -> clump; altri: polvere/gemma
//   Mekanism Chemical Injection (+HCl) x1.50 metalli con filiera: essenza -> shard; altri: polvere/gemma
//   Mekanism Dissolution (+acido solf.) x2.00 solo metalli con filiera: essenza -> slurry sporca
//                                           (poi Chemical Washer + Crystallizer -> crystal)
//
// Esempio ferro (originale: 8 essenze -> 6 lingotti):
//   Create 3 lingotti ogni 8 essenze (37,5% di crushed per essenza), MI 4,5 polveri,
//   Purification 8 clump, Injection 9 shard, Dissolution 2400 mB = 12 crystal.
//
// Lotti: Create lavora un'essenza alla volta (uscite a probabilità); MI e Mekanism lavorano a lotti
// di essenze grandi quanto la ricetta originale, moltiplicati finché la resa originale del lotto è
// almeno AMICI_MYST_LOTTO_MIN (es. diamante: 9 essenze -> 1 diamante, quindi lotto da 36 essenze).
// Ogni livello Mekanism dà almeno 1 oggetto in più del precedente (e della ricetta originale).
//
// La ricetta originale viene rimossa solo se è stata registrata almeno una ricetta alternativa.
// ID verificati sul jar MysticalAgriculture-1.21.1-8.0.29 (data/mysticalagriculture/recipe/essence),
// Mekanism 10.7.19.85, MoreMekanismProcessing 6.8 e Create 6.0.10.
//
// TODO verificare in EMI: che le polveri scelte da getItemFromTag (unify) si fondano davvero in
//   lingotto (uranio: Craftoria rimuove una ricetta MI dust->ingot; alluminio/platino/iridio possono
//   richiedere l'Electric Blast Furnace di MI) e che non esistano altre ricette di altre mod che
//   trasformano le essenze di metalli/gemme (EMI: "usi" di mysticalagriculture:iron_essence ecc.).
// TODO verificare in EMI: le colture disattivate (es. constantan, sapphire) restano senza modifiche
//   e loggano un avviso: è normale se il loro materiale non esiste nel pack.

// Moltiplicatori di resa rispetto alla ricetta originale: ritoccare qui.
const AMICI_MYST_RESA_CREATE = 0.5;
const AMICI_MYST_RESA_MACERATORE = 0.75;
const AMICI_MYST_RESA_PURIFICAZIONE = 1.25;
const AMICI_MYST_RESA_INIEZIONE = 1.5;
const AMICI_MYST_RESA_DISSOLUZIONE = 2.0;

const AMICI_MYST_LOTTO_MIN = 4; // resa originale minima per lotto (MI/Mekanism)
const AMICI_MYST_TEMPO_CREATE = 250; // tick per essenza nelle Crushing Wheels
const AMICI_MYST_MI_EU = 2; // EU/t del Macerator (2 = utilizzabile già in steam age)
const AMICI_MYST_MI_DURATA = 200; // tick per lotto nel Macerator
const AMICI_MYST_MB_PER_CRYSTAL = 200; // mB di slurry pulita per 1 crystal (valore Mekanism)

// Metalli con filiera Mekanism completa (clump/shard/crystal) -> namespace di item e slurry.
// nickel/silver/zinc vengono da moremekanismprocessing: attivi solo perché in
// config/moremekanismprocessing-common.toml hanno processingLevel = 5.
const AMICI_MYST_FILIERA_MEK = {
  iron: 'mekanism',
  gold: 'mekanism',
  copper: 'mekanism',
  tin: 'mekanism',
  lead: 'mekanism',
  osmium: 'mekanism',
  uranium: 'mekanism',
  nickel: 'moremekanismprocessing',
  silver: 'moremekanismprocessing',
  zinc: 'moremekanismprocessing',
};

// Crushed ore di Create che nel pack hanno una lavorazione a valle (washing/fornace).
// aluminum e platinum esistono ma sono rimossi in removals.js, quindi qui non ci sono.
const AMICI_MYST_CRUSHED = ['iron', 'gold', 'copper', 'zinc', 'tin', 'lead', 'osmium', 'uranium', 'silver', 'nickel'];

// materiale: nome nei tag c:*; coltura: nome dell'essenza MA (default = materiale);
// ricetta: id della ricetta MA da rimuovere (senza 'mysticalagriculture:essence/');
// essenze/resa: ricetta originale (N essenze -> resa oggetti); uscita: item fisso (default dal tag c:).
const AMICI_MYST_METALLI = [
  { materiale: 'iron', ricetta: 'minecraft/iron_ingot', essenze: 8, resa: 6 },
  { materiale: 'gold', ricetta: 'minecraft/gold_ingot', essenze: 8, resa: 4 },
  { materiale: 'copper', ricetta: 'minecraft/copper_ingot', essenze: 8, resa: 6 },
  { materiale: 'tin', ricetta: 'common/tin_ingot', essenze: 8, resa: 4 },
  { materiale: 'lead', ricetta: 'common/lead_ingot', essenze: 8, resa: 4 },
  { materiale: 'silver', ricetta: 'common/silver_ingot', essenze: 8, resa: 4 },
  { materiale: 'nickel', ricetta: 'common/nickel_ingot', essenze: 8, resa: 4 },
  { materiale: 'zinc', ricetta: 'common/zinc_ingot', essenze: 8, resa: 4 },
  { materiale: 'osmium', ricetta: 'mekanism/osmium_ingot', essenze: 8, resa: 4 },
  { materiale: 'uranium', ricetta: 'common/uranium_ingot', essenze: 8, resa: 2 },
  { materiale: 'aluminum', ricetta: 'common/aluminum_ingot', essenze: 8, resa: 8 },
  { materiale: 'platinum', ricetta: 'common/platinum_ingot', essenze: 8, resa: 2 },
  { materiale: 'iridium', ricetta: 'common/iridium_ingot', essenze: 8, resa: 2 },
  // Leghe: nessun minerale, quindi niente crushed né filiera Mekanism.
  { materiale: 'bronze', ricetta: 'common/bronze_ingot', essenze: 8, resa: 4 },
  { materiale: 'brass', ricetta: 'common/brass_ingot', essenze: 8, resa: 4 },
  { materiale: 'constantan', ricetta: 'common/constantan_ingot', essenze: 8, resa: 4 },
  { materiale: 'electrum', ricetta: 'common/electrum_ingot', essenze: 8, resa: 4 },
  { materiale: 'invar', ricetta: 'common/invar_ingot', essenze: 8, resa: 4 },
  { materiale: 'steel', ricetta: 'common/steel_ingot', essenze: 8, resa: 3 },
];

const AMICI_MYST_GEMME = [
  { materiale: 'diamond', ricetta: 'minecraft/diamond', essenze: 9, resa: 1, uscita: 'minecraft:diamond' },
  { materiale: 'emerald', ricetta: 'minecraft/emerald', essenze: 9, resa: 1, uscita: 'minecraft:emerald' },
  { materiale: 'lapis', coltura: 'lapis_lazuli', ricetta: 'minecraft/lapis_lazuli', essenze: 8, resa: 12, uscita: 'minecraft:lapis_lazuli' },
  { materiale: 'quartz', coltura: 'nether_quartz', ricetta: 'minecraft/quartz', essenze: 8, resa: 12, uscita: 'minecraft:quartz' },
  { materiale: 'coal', ricetta: 'minecraft/coal', essenze: 8, resa: 12, uscita: 'minecraft:coal' },
  { materiale: 'fluorite', ricetta: 'mekanism/fluorite', essenze: 8, resa: 8 },
  { materiale: 'ruby', ricetta: 'gems/ruby', essenze: 8, resa: 6 },
  { materiale: 'sapphire', ricetta: 'gems/sapphire', essenze: 8, resa: 6 },
  { materiale: 'peridot', ricetta: 'gems/peridot', essenze: 8, resa: 6 },
  { materiale: 'apatite', ricetta: 'gems/apatite', essenze: 8, resa: 16 },
];

// Restituisce [quantità garantita, probabilità dell'oggetto in più] per una resa frazionaria.
function amiciMystSpezzaResa(quantita) {
  let intera = Math.floor(quantita + 1e-9);
  let resto = Math.round((quantita - intera) * 1000) / 1000;
  return [intera, resto];
}

ServerEvents.recipes(event => {
  const create = CreateHelper(event);

  let mekanism = (tipo, materiale, ricetta) => {
    event.custom(ricetta).id(`amici:mystical_raffinazione/mekanism_${tipo}/${materiale}`);
  };

  let mekItemInput = (essenza, quantita) => ({ item: essenza, count: quantita });

  let gestisci = (voce, gemma) => {
    let materiale = voce.materiale;
    let essenza = `mysticalagriculture:${voce.coltura || materiale}_essence`;
    if (!Item.exists(essenza)) return;

    let principale = voce.uscita || getItemFromTag(gemma ? `#c:gems/${materiale}` : `#c:ingots/${materiale}`);
    if (!principale) {
      logWarn(`[amici] Mystical: nessun output per ${materiale}, ricetta originale lasciata`);
      return;
    }

    let polvere = gemma ? false : getItemFromTag(`#c:dusts/${materiale}`);
    let pepita = gemma ? false : getItemFromTag(`#c:nuggets/${materiale}`);
    let filiera = gemma ? null : AMICI_MYST_FILIERA_MEK[materiale];
    // Per i metalli senza filiera Mekanism le macchine Mekanism danno la polvere (o il lingotto se manca).
    let uscitaMek = gemma ? principale : (polvere || principale);

    let lotti = Math.ceil(AMICI_MYST_LOTTO_MIN / voce.resa);
    let lotto = voce.essenze * lotti;
    let base = voce.resa * lotti;
    let registrate = 0;

    // 1) Create Crushing Wheels: un'essenza alla volta, uscite a probabilità.
    let perEssenza = (voce.resa / voce.essenze) * AMICI_MYST_RESA_CREATE;
    let uscitaCreate = null;
    if (gemma) uscitaCreate = principale;
    else if (AMICI_MYST_CRUSHED.includes(materiale)) uscitaCreate = `create:crushed_raw_${materiale}`;
    else if (pepita) {
      uscitaCreate = pepita;
      perEssenza *= 9;
    }
    if (uscitaCreate) {
      let [intera, resto] = amiciMystSpezzaResa(perEssenza);
      let ricetta = create.crushing(AMICI_MYST_TEMPO_CREATE).itemIn(essenza);
      if (intera > 0) ricetta.itemOut(`${intera}x ${uscitaCreate}`);
      if (resto > 0) ricetta.itemOut(uscitaCreate, resto);
      ricetta.id(`amici:mystical_raffinazione/create_crushing/${materiale}`);
      registrate++;
    }

    // 2) Modern Industrialization Macerator: metalli -> polvere, gemme -> gemma.
    let uscitaMI = gemma ? principale : polvere;
    if (uscitaMI) {
      let [intera, resto] = amiciMystSpezzaResa(base * AMICI_MYST_RESA_MACERATORE);
      let uscite = [];
      if (intera > 0) uscite.push({ item: uscitaMI, amount: intera });
      if (resto > 0) uscite.push({ item: uscitaMI, amount: 1, probability: resto });
      event.custom({
        type: 'modern_industrialization:macerator',
        eu: AMICI_MYST_MI_EU,
        duration: AMICI_MYST_MI_DURATA,
        item_inputs: [{ item: essenza, amount: lotto }],
        item_outputs: uscite,
      }).id(`amici:mystical_raffinazione/mi_macerator/${materiale}`);
      registrate++;
    }

    // 3-5) Mekanism: ogni livello dà almeno 1 in più del precedente.
    let purificazione = Math.max(base + 1, Math.round(base * AMICI_MYST_RESA_PURIFICAZIONE));
    let iniezione = Math.max(purificazione + 1, Math.round(base * AMICI_MYST_RESA_INIEZIONE));
    let dissoluzione = Math.max(iniezione + 1, Math.round(base * AMICI_MYST_RESA_DISSOLUZIONE));

    let clump = filiera ? `${filiera}:clump_${materiale}` : uscitaMek;
    let shard = filiera ? `${filiera}:shard_${materiale}` : uscitaMek;

    if (Item.exists(clump)) {
      mekanism('purifying', materiale, {
        type: 'mekanism:purifying',
        chemical_input: { amount: 1, chemical: 'mekanism:oxygen' },
        item_input: mekItemInput(essenza, lotto),
        output: { count: purificazione, id: clump },
        per_tick_usage: true,
      });
      registrate++;
    }

    if (Item.exists(shard)) {
      mekanism('injecting', materiale, {
        type: 'mekanism:injecting',
        chemical_input: { amount: 1, chemical: 'mekanism:hydrogen_chloride' },
        item_input: mekItemInput(essenza, lotto),
        output: { count: iniezione, id: shard },
        per_tick_usage: true,
      });
      registrate++;
    }

    if (filiera) {
      // La slurry sporca segue la filiera esistente: Chemical Washer -> Crystallizer -> crystal.
      mekanism('dissolution', materiale, {
        type: 'mekanism:dissolution',
        chemical_input: { amount: 1, chemical: 'mekanism:sulfuric_acid' },
        item_input: mekItemInput(essenza, lotto),
        output: { amount: dissoluzione * AMICI_MYST_MB_PER_CRYSTAL, id: `${filiera}:dirty_${materiale}` },
        per_tick_usage: true,
      });
      registrate++;
    }

    if (registrate > 0) event.remove({ id: `mysticalagriculture:essence/${voce.ricetta}` });
    else logWarn(`[amici] Mystical: nessuna raffinazione per ${materiale}, ricetta originale lasciata`);
  };

  AMICI_MYST_METALLI.forEach(voce => gestisci(voce, false));
  AMICI_MYST_GEMME.forEach(voce => gestisci(voce, true));
});
