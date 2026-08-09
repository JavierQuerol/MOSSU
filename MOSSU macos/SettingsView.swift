import SwiftUI

/// Ventana de ajustes de MOSSU. Todo lo configurable vive aquí; el menú de la
/// barra se queda con el estado y las acciones del día a día.
struct SettingsView: View {
    @ObservedObject private var model = SettingsModel.shared

    var body: some View {
        TabView(selection: $model.selectedTab) {
            scrollable { GeneralSettingsView() }
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsModel.Tab.general)

            scrollable { ScheduleSettingsView() }
                .tabItem { Label("Actualizaciones", systemImage: "clock") }
                .tag(SettingsModel.Tab.schedule)

            scrollable { CalendarSettingsView() }
                .tabItem { Label("Calendario", systemImage: "calendar") }
                .tag(SettingsModel.Tab.calendar)

            scrollable { QuickLinksSettingsView() }
                .tabItem { Label("Atajos", systemImage: "keyboard") }
                .tag(SettingsModel.Tab.shortcuts)
        }
        .padding(14)
        // Solo límites: el tamaño de arranque lo pone SettingsWindowController.
        .frame(minWidth: 700, maxWidth: .infinity,
               minHeight: 480, maxHeight: .infinity)
    }

    /// Cada pestaña scrollea por su cuenta: así ninguna se corta aunque la ventana
    /// sea más baja que su contenido.
    private func scrollable<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Sección con título, para que las cuatro pestañas se vean iguales.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox(label: Text(title)) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
    }
}
