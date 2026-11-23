// Craftoria Amici: bilanciamento di Mystical Agriculture (issue #1, punti 1 e 2).
//
// 1) TIER LEGATI ALLE ERE DEL PACK
//    La ricetta al banco "4 essenze + cristallo d'infusione = 1 essenza del tier successivo" resta,
//    ma da Tertium in su serve anche un CATALIZZATORE: un componente dell'era tecnologica giusta.
//    Il catalizzatore NON si consuma (resta nella griglia come il cristallo): è un cancello di
//    progressione, non un costo per ogni essenza. Per farlo consumare a ogni craft mettere
//    AMICI_MYST_CATALIZZATORE_CONSUMATO = true.
//
//      Tertium    Create                      create:precision_mechanism
//      Imperium   MI Electric Age / Mekanism  analog_circuit oppure advanced_control_circuit
//      Supremium  MI Quantum Age              modern_industrialization:quantum_circuit
//
//    I semi seguono da soli: ogni seme chiede 4 essenze del proprio tier.
//
// 2) SEMI LEGGENDARI
//    I semi più forti non vengono rimossi: la loro infusione diventa un traguardo endgame.
//    Originale (8 piedistalli): 4 materiali + 4 essenze Supremium.
//    Nuova:                     2 materiali + 4 essenze Supremium + 2 componenti endgame.
//
// ID verificati sul jar MysticalAgriculture-1.21.1-8.0.29: le ricette dei semi sono JSON normali
// (mysticalagriculture:seed/infusion/<coltura>, più seed/crafting/<coltura> se abilitate da config),
// non ricette dinamiche, quindi si possono togliere per ID.

const AMICI_MYST_CATALIZZATORE_CONSUMATO = false;

// essenza: tier prodotto; base: essenza del tier precedente; catalizzatore: uno o più item alternativi.
const AMICI_MYST_TIER = [
  {
    essenza: 'tertium',
    base: 'prudentium',
    catalizzatore: ['create:precision_mechanism'],
  },
  {
    essenza: 'imperium',
    base: 'tertium',
    catalizzatore: ['modern_industrialization:analog_circuit', 'mekanism:advanced_control_circuit'],
  },
  {
    essenza: 'supremium',
    base: 'imperium',
    catalizzatore: ['modern_industrialization:quantum_circuit'],
  },
];

// coltura: nome della coltura MA; materiale: ingrediente originale del seme;
// endgame: componente che sostituisce 2 dei 4 materiali.
const AMICI_MYST_SEMI_LEGGENDARI = [
  { coltura: 'netherite', materiale: 'minecraft:netherite_ingot', endgame: 'modern_industrialization:quantum_upgrade' },
  // Il materiale è il barattolo d'anime pieno di wither skeleton: si usa l'ingrediente di MA.
  { coltura: 'wither_skeleton', materiale: null, endgame: 'mekanism:ultimate_control_circuit' },
  { coltura: 'iridium', materiale: '#c:ingots/iridium', endgame: 'replication:replica_ingot' },
  { coltura: 'platinum', materiale: '#c:ingots/platinum', endgame: 'mekanism:alloy_atomic' },
  { coltura: 'niotic_crystal', materiale: 'powah:crystal_niotic', endgame: 'mekanism:pellet_polonium' },
  { coltura: 'spirited_crystal', materiale: 'powah:crystal_spirited', endgame: 'powah:crystal_nitro' },
];

function amiciMystIngrediente(valore) {
  return valore.startsWith('#') ? { tag: valore.substring(1) } : { item: valore };
}

ServerEvents.recipes(event => {
  // 1) Tier: 4 essenze + cristallo d'infusione + catalizzatore.
  AMICI_MYST_TIER.forEach(tier => {
    let risultato = `mysticalagriculture:${tier.essenza}_essence`;
    let catalizzatori = tier.catalizzatore.filter(id => Item.exists(id));
    if (!Item.exists(risultato) || catalizzatori.length === 0) {
      logWarn(`[amici] Mystical: nessun catalizzatore per ${tier.essenza}, ricetta originale lasciata`);
      return;
    }

    event.remove({ id: risultato });
    let ricetta = event.shaped(risultato, [' # ', '#X#', 'C# '], {
      '#': `mysticalagriculture:${tier.base}_essence`,
      X: '#mysticalagriculture:infusion_crystals',
      C: catalizzatori,
    });
    if (!AMICI_MYST_CATALIZZATORE_CONSUMATO) {
      catalizzatori.forEach(id => ricetta.keepIngredient(id));
    }
    ricetta.id(`amici:mystical_bilanciamento/${tier.essenza}_essence`);
  });

  // 2) Semi leggendari: infusione endgame al posto di quella originale.
  AMICI_MYST_SEMI_LEGGENDARI.forEach(seme => {
    let semi = `mysticalagriculture:${seme.coltura}_seeds`;
    if (!Item.exists(semi) || !Item.exists(seme.endgame)) {
      logWarn(`[amici] Mystical: seme leggendario ${seme.coltura} saltato, ricetta originale lasciata`);
      return;
    }

    let coltura = `mysticalagriculture:${seme.coltura}`;
    let componente = nome => ({ type: 'mysticalagriculture:crop_component', component: nome, crop: coltura });
    let materiale = seme.materiale ? amiciMystIngrediente(seme.materiale) : componente('material');
    let essenza = componente('essence');
    let endgame = { item: seme.endgame };

    event.remove({ id: `mysticalagriculture:seed/infusion/${seme.coltura}` });
    event.remove({ id: `mysticalagriculture:seed/crafting/${seme.coltura}` });
    event
      .custom({
        type: 'mysticalagriculture:infusion',
        input: componente('seed'),
        // Ordine dei piedistalli: materiali e componenti endgame alternati alle essenze.
        ingredients: [materiale, essenza, endgame, essenza, materiale, essenza, endgame, essenza],
        result: { count: 1, id: semi },
      })
      .id(`amici:mystical_bilanciamento/semi/${seme.coltura}`);
  });
});
