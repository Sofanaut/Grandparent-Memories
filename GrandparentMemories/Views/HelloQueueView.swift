//
//  HelloQueueView.swift
//  GrandparentMemories
//
//  Weekly Hello Queue management
//

import SwiftUI
import CoreData

struct HelloQueueView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
    private var grandchildren: FetchedResults<CDGrandchild>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var memories: FetchedResults<CDMemory>

    @State private var selectedGrandchildID: UUID?
    @State private var startDate = Date()
    @State private var isEnabled = false
    @State private var editingMemory: EditableMemory?

    private var selectedGrandchild: CDGrandchild? {
        if let id = selectedGrandchildID {
            return grandchildren.first(where: { $0.id == id })
        }
        return grandchildren.first
    }

    private var queueItems: [CDMemory] {
        guard let grandchild = selectedGrandchild else { return [] }
        return memories.filter { memory in
            guard memory.privacy == MemoryPrivacy.helloQueue.rawValue else { return false }
            guard memory.isReleased == false || memory.isReleased == nil else { return false }
            let set = memory.grandchildren as? Set<CDGrandchild> ?? []
            return set.contains(where: { $0.id == grandchild.id })
        }
        .sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Heartbeats send one memory each week to a chosen grandchild.")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .padding(.vertical, 4)
                }
                if let grandchild = selectedGrandchild {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Viewing")
                                .font(.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(grandchildren) { child in
                                        Button {
                                            selectedGrandchildID = child.id
                                        } label: {
                                            Text(child.name ?? "Grandchild")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(isSelected(child) ? .white : DesignSystem.Colors.textPrimary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(
                                                    isSelected(child) ? DesignSystem.Colors.accent : DesignSystem.Colors.backgroundTertiary,
                                                    in: Capsule()
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        Toggle(isOn: Binding(
                            get: { isEnabled },
                            set: { newValue in
                                isEnabled = newValue
                                if let id = grandchild.id {
                                    HelloQueueManager.shared.setEnabled(newValue, for: id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Weekly Release")
                                Text("Release one heartbeat each week after the start date")
                                    .font(.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                        }

                        DatePicker("Start Date & Time", selection: Binding(
                            get: { startDate },
                            set: { newValue in
                                startDate = newValue
                                if let id = grandchild.id {
                                    HelloQueueManager.shared.setStartDate(newValue, for: id)
                                }
                            }
                        ), displayedComponents: [.date, .hourAndMinute])
                    } header: {
                        Text("Heartbeats")
                    }

                    Section {
                        if queueItems.isEmpty {
                            Text("No items in the queue yet")
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        } else {
                            ForEach(queueItems) { memory in
                                HStack(spacing: 12) {
                                    heartbeatThumbnail(for: memory)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(heartbeatTitle(for: memory))
                                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                                        if let type = memory.memoryType, !type.isEmpty {
                                            Text(type)
                                                .font(.caption)
                                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                        }
                                        Text(memory.date?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                            .font(.caption)
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    }
                                    Spacer()
                                    Button {
                                        editingMemory = EditableMemory(memory: memory)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .onDelete(perform: deleteItems)
                        }
                    } header: {
                        Text("Queued Items")
                    } footer: {
                        Text("These will release one per week once the start date arrives.")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                } else {
                    Text("Add a grandchild to start Heartbeats.")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .navigationTitle("Heartbeats")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingMemory) { item in
                HeartbeatEditView(memory: item.memory)
            }
            .onAppear {
                if selectedGrandchildID == nil {
                    selectedGrandchildID = grandchildren.first?.id
                }
                refreshSettings()
            }
            .onChange(of: selectedGrandchildID) { _, _ in
                refreshSettings()
            }
        }
    }

    private func refreshSettings() {
        guard let id = selectedGrandchild?.id else { return }
        isEnabled = HelloQueueManager.shared.isEnabled(for: id)
        startDate = HelloQueueManager.shared.startDate(for: id) ?? Date()
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let memory = queueItems[index]
            viewContext.delete(memory)
        }
        try? viewContext.save()
    }

    private func heartbeatTitle(for memory: CDMemory) -> String {
        let trimmed = memory.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private func isSelected(_ grandchild: CDGrandchild) -> Bool {
        let currentID = selectedGrandchildID ?? selectedGrandchild?.id
        return currentID == grandchild.id
    }

    @ViewBuilder
    private func heartbeatThumbnail(for memory: CDMemory) -> some View {
        let imageData = memory.videoThumbnailData ?? memory.displayPhotoData
        if let data = imageData {
            CachedAsyncImage(data: data)
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: MemoryType(rawValue: memory.memoryType ?? "")?.icon ?? "heart.fill")
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 56, height: 56)
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct EditableMemory: Identifiable {
    let memory: CDMemory
    var id: NSManagedObjectID { memory.objectID }
}

struct HeartbeatEditView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    let memory: CDMemory
    @State private var titleText: String
    @State private var noteText: String

    init(memory: CDMemory) {
        self.memory = memory
        _titleText = State(initialValue: memory.title ?? "")
        _noteText = State(initialValue: memory.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Add a title", text: $titleText)
                }
                Section("Note") {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 120)
                }
                Section {
                    Button("Delete Heartbeat", role: .destructive) {
                        deleteHeartbeat()
                    }
                }
            }
            .navigationTitle("Edit Heartbeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
        }
    }

    private func saveChanges() {
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        memory.title = trimmedTitle.isEmpty ? nil : trimmedTitle
        memory.note = trimmedNote.isEmpty ? nil : trimmedNote
        try? viewContext.save()
        dismiss()
    }

    private func deleteHeartbeat() {
        viewContext.delete(memory)
        try? viewContext.save()
        dismiss()
    }
}

#Preview {
    HelloQueueView()
        .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
}
