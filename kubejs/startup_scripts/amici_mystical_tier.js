// Craftoria Amici: tier delle colture di Mystical Agriculture (issue #1).
//
// Diamante e smeraldo nascono al tier 5 (Supremium), che nel pack è legato alla MI Quantum Age:
// a quel punto i loro semi non servono più. Scendono al tier 4 (Imperium), come l'oro.
// Le ricette dei semi seguono da sole: usano l'essenza del tier della coltura.
//
// È uno startup script perché il tier deve essere uguale su client e server.

const AMICI_MYST_TIER_COLTURE = {
  diamond: 'FOUR',
  emerald: 'FOUR',
};

StartupEvents.postInit(() => {
  if (!Platform.isLoaded('mysticalagriculture')) return;

  const $CropTier = Java.loadClass('com.blakebr0.mysticalagriculture.api.crop.CropTier');
  const $API = Java.loadClass('com.blakebr0.mysticalagriculture.api.MysticalAgricultureAPI');
  const registro = $API.getCropRegistry();

  Object.keys(AMICI_MYST_TIER_COLTURE).forEach(nome => {
    let coltura = registro.getCropById(ID.mc(`mysticalagriculture:${nome}`));
    if (!coltura) {
      console.warn(`[amici] Mystical: coltura ${nome} non trovata, tier non modificato`);
      return;
    }
    coltura.setTier($CropTier[AMICI_MYST_TIER_COLTURE[nome]]);
  });
});
