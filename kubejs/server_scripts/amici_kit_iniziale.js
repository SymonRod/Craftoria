// Craftoria Amici: mini kit di sopravvivenza al primo accesso.
// File separato da first_join.js (di Craftoria) per non confliggere con gli aggiornamenti a monte.
// Lo stage è diverso da 'first_join': chi era già entrato prima di questo script riceve il kit una volta.

const KIT_INIZIALE_STAGE = 'amici_kit_iniziale';

const KIT_INIZIALE = [
  'minecraft:stone_sword',
  '4x minecraft:torch',
  '16x minecraft:bread',
  'comforts:sleeping_bag_white',
];

PlayerEvents.loggedIn(event => {
  const player = event.player;
  if (player.stages.has(KIT_INIZIALE_STAGE)) return;

  KIT_INIZIALE.forEach(item => player.give(Item.of(item)));
  player.stages.add(KIT_INIZIALE_STAGE);
  player.tell(Text.gold('Hai ricevuto un mini kit di sopravvivenza. Buona fortuna!'));
});
