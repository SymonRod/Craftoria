// Craftoria Amici: mini kit di sopravvivenza.
// Dato in automatico al primo accesso; poi si può richiedere con /kitiniziale al massimo una volta ogni 24 ore.
// File separato da first_join.js (di Craftoria) per non confliggere con gli aggiornamenti a monte.
// Lo stage è diverso da 'first_join': chi era già entrato prima di questo script riceve il kit una volta.

const KIT_INIZIALE_STAGE = 'amici_kit_iniziale';
const KIT_INIZIALE_ULTIMO = 'amici_kit_iniziale_ultimo'; // ms dall'epoch, in persistentData del giocatore
const KIT_INIZIALE_ATTESA_MS = 24 * 60 * 60 * 1000;

const KIT_INIZIALE = [
  'minecraft:stone_sword',
  '4x minecraft:torch',
  '16x minecraft:bread',
  'comforts:sleeping_bag_white',
];

function kitInizialeDai(player) {
  KIT_INIZIALE.forEach(item => player.give(Item.of(item)));
  player.persistentData.putLong(KIT_INIZIALE_ULTIMO, Date.now());
  player.tell(Text.gold('Hai ricevuto un mini kit di sopravvivenza. Buona fortuna!'));
}

PlayerEvents.loggedIn(event => {
  const player = event.player;
  if (player.stages.has(KIT_INIZIALE_STAGE)) return;

  player.stages.add(KIT_INIZIALE_STAGE);
  kitInizialeDai(player);
});

ServerEvents.commandRegistry(event => {
  const { commands: Commands } = event;

  event.register(
    Commands.literal('kitiniziale').executes(ctx => {
      const player = ctx.source.playerOrException;
      const ultimo = player.persistentData.getLong(KIT_INIZIALE_ULTIMO);
      const mancano = ultimo + KIT_INIZIALE_ATTESA_MS - Date.now();

      if (ultimo > 0 && mancano > 0) {
        const totaleMinuti = Math.ceil(mancano / 60000);
        const ore = Math.floor(totaleMinuti / 60);
        const minuti = totaleMinuti % 60;
        player.tell(Text.red(`Puoi riprendere il kit tra ${ore} h e ${minuti} min.`));
        return 0;
      }

      kitInizialeDai(player);
      return 1;
    })
  );
});
