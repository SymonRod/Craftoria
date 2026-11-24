// Craftoria Amici: teleport dalla mappa di Xaero (M, tasto destro, "Teleport Here") anche per chi non è op.
// Xaero di default manda /tp, che richiede op. Il server impone a tutti i client (profilo server di Xaero,
// config/xaero/world-map/server_profiles/default.cfg) di usare invece /tpmap, definito qui con un'attesa
// tra un teleport e l'altro. Gli op non hanno attesa.
//
// Uso: /tpmap <x> <y> <z> [dimensione]   (y può essere ~, come la manda Xaero quando non la conosce)

const TP_MAPPA_ULTIMO = 'amici_tp_mappa_ultimo'; // ms dall'epoch, in persistentData del giocatore
const TP_MAPPA_ATTESA_MS = 5 * 60 * 1000;

const $AmiciVec3Argument = Java.loadClass('net.minecraft.commands.arguments.coordinates.Vec3Argument');
const $AmiciDimensionArgument = Java.loadClass('net.minecraft.commands.arguments.DimensionArgument');

function tpMappaEsegui(ctx, conDimensione) {
  const source = ctx.source;
  const player = source.playerOrException;
  const pos = $AmiciVec3Argument.getVec3(ctx, 'pos');
  const level = conDimensione ? $AmiciDimensionArgument.getDimension(ctx, 'dimensione') : player.serverLevel();

  if (!source.hasPermission(2)) {
    const ultimo = player.persistentData.getLong(TP_MAPPA_ULTIMO);
    const mancano = ultimo + TP_MAPPA_ATTESA_MS - Date.now();
    if (ultimo > 0 && mancano > 0) {
      const totaleSecondi = Math.ceil(mancano / 1000);
      const minuti = Math.floor(totaleSecondi / 60);
      const secondi = totaleSecondi % 60;
      player.tell(Text.translatable('amici.tp_mappa.attesa', `${minuti}`, `${secondi}`).red());
      return 0;
    }
  }

  player.teleportTo(level, pos.x(), pos.y(), pos.z(), player.getYRot(), player.getXRot());
  player.persistentData.putLong(TP_MAPPA_ULTIMO, Date.now());
  return 1;
}

ServerEvents.commandRegistry(event => {
  const { commands: Commands } = event;

  event.register(
    Commands.literal('tpmap').then(
      Commands.argument('pos', $AmiciVec3Argument.vec3())
        .executes(ctx => tpMappaEsegui(ctx, false))
        .then(
          Commands.argument('dimensione', $AmiciDimensionArgument.dimension())
            .executes(ctx => tpMappaEsegui(ctx, true))
        )
    )
  );
});
