//
//  GrandchildVaultView.swift
//  GrandparentMemories
//
//  Beautiful vault screen showing future gifts
//

import SwiftUI
import CoreData

struct GrandchildVaultView: View {
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    let grandchild: CDGrandchild
    
    var grandparentNames: String {
        let names = contributors.map { $0.displayName }.joined(separator: " & ")
        return names.isEmpty ? "Your grandparents" : names
    }
    
    var body: some View {
        ZStack {
            // Soft gradient background
            LinearGradient(
                colors: [
                    DesignSystem.Colors.backgroundPrimary,
                    Color(hex: "FFF8F0"),
                    Color(hex: "FFE8D6")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Floating sparkles
            FloatingSparklesView()
            
            // Main content
            ScrollView {
                VStack(spacing: 32) {
                    Spacer()
                        .frame(height: 60)
                    
                    // Soft glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    DesignSystem.Colors.accent.opacity(0.2),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .overlay(
                            Image(systemName: "gift.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(DesignSystem.Colors.primaryGradient)
                        )
                    
                    VStack(spacing: 24) {
                        // Personalized opening
                        Text("\(grandparentNames) have\nprepared special gifts\nfor you.")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        // Divider
                        Rectangle()
                            .fill(DesignSystem.Colors.accent.opacity(0.3))
                            .frame(width: 100, height: 2)
                            .padding(.vertical, 8)
                        
                        // Poetic message
                        VStack(spacing: 20) {
                            Text("Some gifts aren't meant\nto be opened today.")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            
                            Text("They've carefully chosen\nwhen you'll receive each\nmemory.")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            
                            Text("Some wait for birthdays.")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            
                            Text("Some for milestones.")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            
                            Text("Some for when you're ready.")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        
                        // Divider
                        Rectangle()
                            .fill(DesignSystem.Colors.accent.opacity(0.3))
                            .frame(width: 100, height: 2)
                            .padding(.vertical, 8)
                        
                        // Final message
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Text("Trust the timing.")
                                    .font(DesignSystem.Typography.title3)
                                    .fontWeight(.medium)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                
                                Text("✨")
                                    .font(.title2)
                            }
                            
                            Text("They'll arrive exactly\nwhen you need them.")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    }
                    
                    Spacer()
                        .frame(height: 60)
                }
                .padding()
            }
        }
    }
}

// Floating sparkles animation
struct FloatingSparklesView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            ForEach(0..<8) { index in
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.3))
                    .frame(width: 4, height: 4)
                    .offset(
                        x: CGFloat.random(in: -150...150),
                        y: animate ? -600 : 600
                    )
                    .animation(
                        .linear(duration: Double.random(in: 8...12))
                        .repeatForever(autoreverses: false)
                        .delay(Double(index) * 0.5),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
    }
}


#Preview {
    // Create in-memory Core Data stack for preview
    let container = NSPersistentContainer(name: "GrandparentMemories")
    let description = NSPersistentStoreDescription()
    description.type = NSInMemoryStoreType
    container.persistentStoreDescriptions = [description]
    
    container.loadPersistentStores { _, error in
        if let error = error {
            fatalError("Failed to load preview store: \(error)")
        }
    }
    
    let context = container.viewContext
    let grandchild = CDGrandchild(context: context)
    grandchild.id = UUID()
    grandchild.name = "Emma"
    grandchild.birthDate = Date()
    
    return GrandchildVaultView(grandchild: grandchild)
        .environment(\.managedObjectContext, context)
}
