import SwiftUI

struct CategoryModalView: View {
    let existing: Category?
    let onSave: (Category) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var useKeyword: Bool = false
    @State private var keywordText: String = ""
    @State private var useType: Bool = false
    @State private var selectedTypes: Set<String> = []
    @State private var logic: Category.ConditionLogic = .and

    private let allTypes = FileTypeCategory.allCases

    init(existing: Category? = nil, onSave: @escaping (Category) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.onSave   = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "카테고리 추가" : "카테고리 수정")
                .font(.system(size: 13, weight: .semibold))

            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text("카테고리명").font(.system(size: 11, weight: .medium))
                TextField("이름 입력", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Conditions
            VStack(alignment: .leading, spacing: 8) {
                Text("분류 조건").font(.system(size: 11, weight: .medium))

                // Keyword
                HStack(spacing: 6) {
                    Toggle("", isOn: $useKeyword).labelsHidden().controlSize(.small)
                    Text("키워드").font(.system(size: 11))
                    if useKeyword {
                        TextField("쉼표로 구분", text: $keywordText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                    }
                }

                // File type
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Toggle("", isOn: $useType).labelsHidden().controlSize(.small)
                        Text("파일 타입").font(.system(size: 11))
                    }
                    if useType {
                        HStack(spacing: 6) {
                            ForEach(allTypes, id: \.rawValue) { ft in
                                TypePill(
                                    label: ft.rawValue,
                                    extensions: ft.extensions,
                                    isSelected: selectedTypes.contains(ft.rawValue)
                                ) {
                                    if selectedTypes.contains(ft.rawValue) {
                                        selectedTypes.remove(ft.rawValue)
                                    } else {
                                        selectedTypes.insert(ft.rawValue)
                                    }
                                }
                            }
                        }
                    }
                }

                // AND / OR when both active
                if useKeyword && useType {
                    HStack(spacing: 8) {
                        Text("조건 처리").font(.system(size: 11))
                        Picker("", selection: $logic) {
                            Text("AND (둘 다 해당)").tag(Category.ConditionLogic.and)
                            Text("OR (하나라도 해당)").tag(Category.ConditionLogic.or)
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 180)
                    }
                }
            }

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "추가" : "저장") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { populate() }
    }

    // MARK: - Helpers

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (useKeyword || useType)
    }

    private func populate() {
        guard let cat = existing else { return }
        name = cat.name
        if cat.conditionType == .keyword || cat.conditionType == .both {
            useKeyword = true
            keywordText = cat.keywords.joined(separator: ", ")
        }
        if cat.conditionType == .type || cat.conditionType == .both {
            useType = true
            selectedTypes = Set(cat.types)
        }
        logic = cat.logic ?? .and
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let keywords = keywordText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let condType: Category.ConditionKind
        if useKeyword && useType       { condType = .both }
        else if useKeyword             { condType = .keyword }
        else                           { condType = .type }

        let cat = Category(
            id: existing?.id ?? UUID().uuidString,
            num: existing?.num ?? 0,
            name: trimmedName,
            conditionType: condType,
            types: useType ? Array(selectedTypes) : [],
            keywords: useKeyword ? keywords : [],
            logic: (useKeyword && useType) ? logic : nil,
            outputIdx: existing?.outputIdx ?? 0
        )
        onSave(cat)
    }
}

// MARK: - TypePill

private struct TypePill: View {
    let label: String
    let extensions: [String]
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(NSColor.controlColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(extensions.joined(separator: "  "))
    }
}
