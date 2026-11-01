import SwiftUI

/// Ventana de ajustes de MOSSU. Todo lo configurable vive aquí; el menú de la
/// barra se queda con el estado y las acciones del día a día.
///
/// Como en Ajustes del Sistema, las secciones van en una barra lateral y la
/// elegida se ve a la derecha.
struct SettingsView: View {
    @ObservedObject private var model = SettingsModel.shared

    var body: some View {
        Group {
            if #available(macOS 13, *) {
                SettingsSplitView(sidebar: sidebar, detail: detail)
            } else {
                NavigationView {
                    sidebar
                        .frame(minWidth: sidebarWidth)
                    detail
                }
            }
        }
        // Solo límites: el tamaño de arranque lo pone SettingsWindowController.
        .frame(minWidth: 760, maxWidth: .infinity,
               minHeight: 480, maxHeight: .infinity)
    }

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(SettingsModel.Tab.allCases, id: \.self) { tab in
                Label {
                    Text(tab.title)
                } icon: {
                    SidebarIcon(tab: tab)
                }
                .tag(tab)
            }
        }
        .listStyle(.sidebar)
    }

    /// La lista deja quedarse sin selección (⌘-clic en la fila marcada), pero
    /// siempre tiene que haber una sección abierta. Reasignar la actual avisa a
    /// SwiftUI igualmente, y la lista vuelve a marcarla.
    private var selection: Binding<SettingsModel.Tab?> {
        Binding(
            get: { model.selectedTab },
            set: { model.selectedTab = $0 ?? model.selectedTab }
        )
    }

    /// Cada sección scrollea por su cuenta: así ninguna se corta aunque la ventana
    /// sea más baja que su contenido. Con el `id`, al cambiar de sección se empieza
    /// arriba y no donde se quedó el scroll de la anterior.
    private var detail: some View {
        ScrollView {
            switch model.selectedTab {
            case .general:
                GeneralSettingsView()
            case .schedule:
                ScheduleSettingsView()
            case .calendar:
                CalendarSettingsView()
            case .shortcuts:
                QuickLinksSettingsView()
            }
        }
        .id(model.selectedTab)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private let sidebarWidth: CGFloat = 200

/// La barra lateral de SwiftUI se pliega si se arrastra el divisor, y MOSSU no
/// tiene botón ni menú para volver a sacarla: si se pliega, se vuelve a abrir.
@available(macOS 13, *)
private struct SettingsSplitView<Sidebar: View, Detail: View>: View {
    let sidebar: Sidebar
    let detail: Detail

    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(sidebarWidth)
        } detail: {
            detail
        }
        .onChange(of: columnVisibility) { _ in
            columnVisibility = .all
        }
    }
}

/// Icono de sección como los de Ajustes del Sistema: el símbolo en blanco sobre
/// un cuadrado redondeado de color.
private struct SidebarIcon: View {
    let tab: SettingsModel.Tab

    var body: some View {
        Image(systemName: tab.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tab.color)
            )
    }
}

extension SettingsModel.Tab {
    /// Nombre de la sección en la barra lateral y en el título de la ventana.
    var title: String {
        switch self {
        case .general:
            return "General"
        case .schedule:
            return "Actualizaciones"
        case .calendar:
            return "Calendario"
        case .shortcuts:
            return "Atajos"
        }
    }

    fileprivate var symbol: String {
        switch self {
        case .general:
            return "gearshape.fill"
        case .schedule:
            return "clock.fill"
        case .calendar:
            return "calendar"
        case .shortcuts:
            return "keyboard.fill"
        }
    }

    fileprivate var color: Color {
        switch self {
        case .general:
            return .gray
        case .schedule:
            return .blue
        case .calendar:
            return .red
        case .shortcuts:
            return .indigo
        }
    }
}

/// Bloque con título, para que las cuatro secciones se vean iguales.
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
