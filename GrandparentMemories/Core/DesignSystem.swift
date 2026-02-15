//
//  DesignSystem.swift
//  GrandparentMemories
//
//  Created by Tony Smith on 04/02/2026.
//

import SwiftUI
import CoreData

enum DesignSystem {
    
    // MARK: - Colors
    
    enum Colors {
        // Primary - Soft Coral/Peach (warm, inviting)
        static let primary = Color(hex: "FF9B85")
        static let primaryLight = Color(hex: "FFB5A0")
        static let primaryDark = Color(hex: "E8846F")
        
        // Backgrounds - Warm Cream/Ivory
        static let backgroundPrimary = Color(hex: "FFFAF5")
        static let backgroundSecondary = Color(hex: "FFF8F0")
        static let backgroundTertiary = Color(hex: "FFF0E6")
        
        // Accent - Honey Gold (joy, special moments)
        static let accent = Color(hex: "F4A460")
        static let accentLight = Color(hex: "FFB87D")
        static let accentDark = Color(hex: "D4A574")
        
        // Secondary - Soft Sage Green (calm, nurturing)
        static let secondary = Color(hex: "B8C5B0")
        static let secondaryLight = Color(hex: "CCD9C4")
        static let secondaryDark = Color(hex: "9FAF93")
        
        // Teal - Complementary accent (badges, icons, special features) - Grandpa's color
        static let teal = Color(hex: "4EA8A0")
        static let tealLight = Color(hex: "6FBDB7")
        static let tealDark = Color(hex: "3D8A84")
        
        // Purple - Grandma's color
        static let pink = Color(hex: "7B3F90")
        static let pinkLight = Color(hex: "9B5FAF")
        static let pinkDark = Color(hex: "632F75")
        
        // Neutrals
        static let textPrimary = Color(hex: "3D3430")
        static let textSecondary = Color(hex: "6B5F58")
        static let textTertiary = Color(hex: "9B8E87")
        
        // Semantic Colors
        static let success = Color(hex: "8BC34A")
        static let warning = Color(hex: "FFA726")
        static let error = Color(hex: "EF5350")
        
        // Gradients
        static let primaryGradient: LinearGradient = LinearGradient(
            colors: [primary, primaryLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let accentGradient: LinearGradient = LinearGradient(
            colors: [accent, accentLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let warmGradient: LinearGradient = LinearGradient(
            colors: [primaryLight, accentLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let tealGradient: LinearGradient = LinearGradient(
            colors: [teal, tealLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        static let pinkGradient: LinearGradient = LinearGradient(
            colors: [pink, pinkLight],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Typography
    
    enum Typography {
        // Increased sizes for elderly users - easier to read
        static let largeTitle = Font.system(size: 52, weight: .bold, design: .rounded)
        static let title1 = Font.system(size: 38, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 32, weight: .bold, design: .rounded)
        static let title3 = Font.system(size: 26, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 19, weight: .regular, design: .default)
        static let callout = Font.system(size: 18, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 17, weight: .regular, design: .default)
        static let footnote = Font.system(size: 15, weight: .regular, design: .default)
        static let caption = Font.system(size: 14, weight: .regular, design: .default)
    }
    
    // MARK: - Spacing
    
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
    }
    
    // MARK: - Corner Radius
    
    enum CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
    
    // MARK: - Shadows
    
    enum Shadows {
        static let subtle = Shadow(
            color: Color.black.opacity(0.05),
            radius: 8,
            y: 4
        )
        
        static let medium = Shadow(
            color: Color.black.opacity(0.1),
            radius: 12,
            y: 6
        )
        
        static let strong = Shadow(
            color: Color.black.opacity(0.15),
            radius: 16,
            y: 8
        )
    }
    
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        
        init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat) {
            self.color = color
            self.radius = radius
            self.x = x
            self.y = y
        }
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Extensions for Design System

extension View {
    func primaryButton(color: Color? = nil) -> some View {
        self
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                color != nil ?
                    AnyShapeStyle(LinearGradient(colors: [color!, color!.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)) :
                    AnyShapeStyle(DesignSystem.Colors.primaryGradient),
                in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
            )
    }
    
    func secondaryButton() -> some View {
        self
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding()
            .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
    }
    
    func cardStyle() -> some View {
        self
            .padding()
            .background(DesignSystem.Colors.backgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            .shadow(
                color: DesignSystem.Shadows.subtle.color,
                radius: DesignSystem.Shadows.subtle.radius,
                x: DesignSystem.Shadows.subtle.x,
                y: DesignSystem.Shadows.subtle.y
            )
    }
}

// MARK: - Helper for Active Contributor Color

import SwiftUI

@MainActor
func getActiveContributorColor(viewContext: NSManagedObjectContext, activeContributorID: String) -> Color {
    let request = CDContributor.fetchRequest()
    if let uuid = UUID(uuidString: activeContributorID) {
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
    }
    guard let contributors = try? viewContext.fetch(request),
          let activeContributor = contributors.first,
          let colorHex = activeContributor.colorHex else {
        return DesignSystem.Colors.teal
    }
    return Color(hex: colorHex)
}
