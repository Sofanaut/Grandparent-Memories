//
//  GiftSchedulingView.swift
//  GrandparentMemories
//
//  Created by Claude on 2026-02-08.
//

import SwiftUI

struct GiftSchedulingView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedOption: GiftReleaseOption
    @Binding var releaseDate: Date
    @Binding var releaseAge: Int
    
    let grandchildName: String
    let onComplete: () -> Void
    
    @State private var showDatePicker = false
    @State private var showAgePicker = false
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(DesignSystem.Colors.accent)
                        
                        Text("When should \(grandchildName) receive this gift?")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        Text("You can choose to share it now or schedule it for a special moment in the future.")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.horizontal)
                    
                    // Options
                    VStack(spacing: 16) {
                        // Share Now
                        optionCard(
                            title: "Share Now",
                            subtitle: "Available immediately",
                            icon: "sparkles",
                            isSelected: selectedOption == .immediate
                        ) {
                            withAnimation(.spring()) {
                                selectedOption = .immediate
                            }
                        }
                        
                        // Specific Date
                        optionCard(
                            title: "On a Specific Date",
                            subtitle: selectedOption == .specificDate ? releaseDate.formatted(date: .long, time: .omitted) : "Choose a future date",
                            icon: "calendar",
                            isSelected: selectedOption == .specificDate,
                            showChevron: selectedOption == .specificDate
                        ) {
                            withAnimation(.spring()) {
                                selectedOption = .specificDate
                                showDatePicker = true
                            }
                        }
                        
                        // When They Reach an Age
                        optionCard(
                            title: "When They Turn",
                            subtitle: selectedOption == .atAge ? "Age \(releaseAge)" : "Choose an age milestone",
                            icon: "birthday.cake",
                            isSelected: selectedOption == .atAge,
                            showChevron: selectedOption == .atAge
                        ) {
                            withAnimation(.spring()) {
                                selectedOption = .atAge
                                showAgePicker = true
                            }
                        }
                        
                        // Save for Later (Vault)
                        optionCard(
                            title: "Keep in Vault",
                            subtitle: "Not scheduled - you'll decide later",
                            icon: "archivebox.fill",
                            isSelected: selectedOption == .vault
                        ) {
                            withAnimation(.spring()) {
                                selectedOption = .vault
                            }
                        }

                        // Heartbeats
                        optionCard(
                            title: "Heartbeats",
                            subtitle: "Weekly release after the start date",
                            icon: "heart.fill",
                            isSelected: selectedOption == .helloQueue
                        ) {
                            withAnimation(.spring()) {
                                selectedOption = .helloQueue
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle("Schedule Gift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isSaving = true
                        onComplete()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(200))
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
            .sheet(isPresented: $showAgePicker) {
                agePickerSheet
            }
            .allowsHitTesting(!isSaving)
            .overlay(savingOverlay)
        }
    }
    
    // MARK: - Option Card
    
    @ViewBuilder
    private func optionCard(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        showChevron: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.backgroundSecondary)
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(isSelected ? .white : DesignSystem.Colors.accent)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                // Selection indicator or chevron
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
            .padding(16)
            .background(DesignSystem.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? DesignSystem.Colors.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var savingOverlay: some View {
        Group {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Saving...")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(20)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                }
                .transition(.opacity)
            }
        }
    }
    
    // MARK: - Date Picker Sheet
    
    private var datePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    "Release Date",
                    selection: $releaseDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                
                Text("The gift will be released on this date at midnight")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle("Choose Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showDatePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Age Picker Sheet
    
    private var agePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Age", selection: $releaseAge) {
                    ForEach(1...100, id: \.self) { age in
                        Text("\(age) years old").tag(age)
                    }
                }
                .pickerStyle(.wheel)
                .padding()
                
                Text("The gift will be released when they reach this age")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle("Choose Age")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showAgePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Gift Release Option Enum

enum GiftReleaseOption: String, Codable {
    case immediate = "Share Now"
    case specificDate = "Specific Date"
    case atAge = "At Age"
    case vault = "Vault Only"
    case helloQueue = "Hello Queue"
}

#Preview {
    @Previewable @State var option: GiftReleaseOption = .immediate
    @Previewable @State var date = Date()
    @Previewable @State var age = 10
    
    GiftSchedulingView(
        selectedOption: $option,
        releaseDate: $date,
        releaseAge: $age,
        grandchildName: "Emma",
        onComplete: {}
    )
}
