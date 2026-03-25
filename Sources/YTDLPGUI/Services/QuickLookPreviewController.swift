import AppKit
import Foundation
import Quartz
import SwiftUI

@MainActor
final class QuickLookPreviewController: NSObject, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreviewController()

    private var previewItems: [URL] = []
    private var selectedIndex = 0
    private var selectionHandler: ((Int) -> Void)?

    func update(
        items: [URL],
        selectedItemID: URL?,
        onSelectionChange: @escaping (Int) -> Void
    ) {
        previewItems = items
        selectionHandler = onSelectionChange

        if let selectedItemID, let index = items.firstIndex(of: selectedItemID) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }

        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.reloadData()
            if !previewItems.isEmpty {
                panel.currentPreviewItemIndex = selectedIndex
            }
        }
    }

    func present() {
        guard !previewItems.isEmpty else { return }
        QuickLookPanelHostView.activeHost?.showPreviewPanel()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewItems[index] as NSURL
    }

    func previewPanelCurrentPreviewItemIndexDidChange(_ panel: QLPreviewPanel!) {
        selectedIndex = panel.currentPreviewItemIndex
        selectionHandler?(selectedIndex)
    }

    func apply(to panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        if !previewItems.isEmpty {
            panel.currentPreviewItemIndex = selectedIndex
        }
    }

    func clear(from panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

final class QuickLookPanelHostView: NSView {
    static weak var activeHost: QuickLookPanelHostView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            Self.activeHost = self
        } else if Self.activeHost === self {
            Self.activeHost = nil
        }
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            QuickLookPreviewController.shared.apply(to: panel)
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            QuickLookPreviewController.shared.clear(from: panel)
        }
    }

    func showPreviewPanel() {
        guard let panel = QLPreviewPanel.shared() else { return }
        window?.makeFirstResponder(self)
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
    }
}

struct QuickLookPanelBridge: NSViewRepresentable {
    @EnvironmentObject private var viewModel: AppViewModel

    func makeNSView(context: Context) -> QuickLookPanelHostView {
        let view = QuickLookPanelHostView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: QuickLookPanelHostView, context: Context) {
        QuickLookPreviewController.shared.update(
            items: viewModel.libraryStore.items.map(\.url),
            selectedItemID: viewModel.selectedLibraryItemID
        ) { index in
            Task { @MainActor in
                viewModel.selectLibraryItem(at: index)
            }
        }
    }
}
