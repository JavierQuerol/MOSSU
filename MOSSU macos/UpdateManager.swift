import Sparkle

/// Sparkle con un paso más antes de instalar. Sin admin no se puede escribir en
/// /Applications y Sparkle pediría la contraseña de un administrador, que casi nadie
/// tiene; en su lugar, MOSSU consigue admin con LAPS en cuanto se pulsa «Instalar».
final class UpdateManager {
    private let updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: ElevatingUserDriver(hostBundle: .main, delegate: nil),
        delegate: nil
    )

    func start() {
        do {
            try updater.start()
        } catch {
            LogManager.shared.log("⬆️ No pude arrancar el actualizador: \(error.localizedDescription)")
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

/// La interfaz de siempre de Sparkle, pero el «Instalar» no le llega hasta tener admin.
/// Sparkle pide la contraseña al empezar a extraer la descarga, así que basta con
/// retener la respuesta del usuario.
private final class ElevatingUserDriver: SPUStandardUserDriver {
    override func showUpdateFound(with appcastItem: SUAppcastItem,
                                  state: SPUUserUpdateState,
                                  reply: @escaping (SPUUserUpdateChoice) -> Void) {
        super.showUpdateFound(with: appcastItem, state: state) { choice in
            Self.ensureAdmin(before: choice, reply: reply)
        }
    }

    /// La elevación dura 45 minutos: si «Instalar y reiniciar» se queda esperando más,
    /// la sustitución de la app volvería a necesitarla.
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        super.showReady(toInstallAndRelaunch: { choice in
            Self.ensureAdmin(before: choice, reply: reply)
        })
    }

    private static func ensureAdmin(before choice: SPUUserUpdateChoice,
                                    reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard choice == .install else { return reply(choice) }

        LAPSManager.shared.ensureAdmin { isAdmin in
            // Se instala igual: quien sepa una contraseña de administrador aún puede hacerlo.
            if !isAdmin {
                LogManager.shared.log("⬆️ Actualización sin admin: Sparkle pedirá una contraseña de administrador")
            }
            reply(.install)
        }
    }
}
