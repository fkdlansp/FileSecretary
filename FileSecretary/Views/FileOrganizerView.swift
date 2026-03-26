import SwiftUI

struct FileOrganizerView: View {
    @Binding var targetFolders: [URL]

    @ObservedObject var vm: OrganizerViewModel

    var body: some View {
        HStack(spacing: 0) {
            LeftPanelView(vm: vm)
            Divider()
            CategoryListView(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .focusedObject(vm)
        .onAppear {
            for url in targetFolders where !vm.targetFolders.contains(url) {
                vm.addTargetFolder(url)
            }
        }
        .onChange(of: targetFolders) { folders in
            for url in folders where !vm.targetFolders.contains(url) {
                vm.addTargetFolder(url)
            }
        }
        // Duplicate dialog — shown only when a duplicate is actually found.
        // onDismiss ensures the continuation is always resumed even if the user
        // closes the sheet via Escape or clicking outside (not via the buttons).
        .sheet(isPresented: $vm.showDuplicateDialog, onDismiss: { vm.cancelDuplicate() }) {
            DuplicateFileDialog(
                fileName: vm.conflictFile?.lastPathComponent ?? "",
                onConfirm: { mode in vm.confirmDuplicate(mode) },
                onCancel: { vm.cancelDuplicate() }
            )
        }
        // Uncategorized dialog
        .sheet(isPresented: $vm.showUncategorizedDialog, onDismiss: { vm.confirmUncategorized(false) }) {
            UncategorizedDialog(
                fileName: vm.conflictFile?.lastPathComponent ?? "",
                onMoveToEtc: { vm.confirmUncategorized(true) },
                onSkip: { vm.confirmUncategorized(false) }
            )
        }
        // Category conflict dialog
        .sheet(isPresented: $vm.showConflictDialog, onDismiss: { vm.resolveConflict(.skip) }) {
            CategoryConflictDialog(
                fileName: vm.conflictFile?.lastPathComponent ?? "",
                categories: vm.conflictCategories,
                onSelect: { cat in vm.resolveConflict(.useCategory(cat)) },
                onSkip: { vm.resolveConflict(.skip) }
            )
        }
        // Exclude list editor
        .sheet(isPresented: $vm.showExcludeListEditor) {
            ExcludeListView(excludeList: $vm.excludeList)
                .onDisappear { vm.saveSettings() }
        }
    }
}
