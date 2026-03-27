import SwiftUI

struct CategoryListView: View {
    @ObservedObject var vm: OrganizerViewModel

    @State private var showAddModal   = false
    @State private var editingCategory: Category? = nil

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Category list
            List {
                ForEach(vm.categories) { cat in
                    CategoryCardView(
                        category: cat,
                        outputFolders: vm.outputFolders,
                        onEdit: { editingCategory = cat },
                        onRemove: { vm.removeCategory(id: cat.id) },
                        onOutputChange: { idx in
                            var updated = cat
                            updated.outputIdx = idx
                            vm.updateCategory(updated)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove(perform: vm.moveCategory)

                // 기타 (fixed, not movable)
                EtcCategoryRow()
                    .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)

            // MARK: Add button
            HStack {
                Button("+ 카테고리 추가") { showAddModal = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                    .padding(.leading, 12)
                Spacer()
            }
            .padding(.vertical, 6)

            Divider()

            // MARK: Action buttons
            HStack(spacing: 10) {
                // Exclude list button
                Button("제외 목록") { vm.showExcludeListEditor = true }
                    .buttonStyle(ActionButtonStyle(color: Color(NSColor.systemIndigo)))

                Spacer()

                // Undo button
                Button {
                    vm.performUndo()
                } label: {
                    Label("되돌리기 (\(vm.undoCount))", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11))
                }
                .buttonStyle(ActionButtonStyle(color: vm.undoCount > 0 ? Color(NSColor.systemOrange) : Color(NSColor.systemGray)))
                .disabled(vm.undoCount == 0)

                // Organize button
                Button {
                    vm.startOrganize()
                } label: {
                    if vm.isOrganizing {
                        ProgressView().controlSize(.mini)
                            .padding(.horizontal, 8)
                    } else {
                        Text("지금 정리하기")
                    }
                }
                .buttonStyle(ActionButtonStyle(color: Color(NSColor.systemGreen)))
                .disabled(vm.targetFolders.isEmpty || vm.isOrganizing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $showAddModal) {
            CategoryModalView(onSave: { cat in
                vm.addCategory(cat)
                showAddModal = false
            }, onCancel: { showAddModal = false })
        }
        .sheet(item: $editingCategory) { cat in
            CategoryModalView(existing: cat, onSave: { updated in
                vm.updateCategory(updated)
                editingCategory = nil
            }, onCancel: { editingCategory = nil })
        }
    }
}

// MARK: - 기타 row (fixed, no drag/delete)

private struct EtcCategoryRow: View {
    var body: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 16)
            Text("—")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text("기타")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text("항상 고정")
                .font(.system(size: 9))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .foregroundColor(.secondary)
                .cornerRadius(4)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - ActionButtonStyle

struct ActionButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundColor(.white)
            .cornerRadius(6)
    }
}
