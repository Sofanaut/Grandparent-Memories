//
//  Enums.swift
//  GrandparentMemories
//
//  Common enums used throughout the app
//  Extracted from Models.swift for use with Core Data
//

import Foundation
import SwiftUI

// MARK: - Contributor Enums

enum ContributorRole: String, Codable, CaseIterable {
    case grandpa = "Grandpa"
    case grandma = "Grandma"

    var defaultColor: String {
        switch self {
        case .grandpa: return "4EA8A0" // Teal
        case .grandma: return "7B3F90" // Purple
        }
    }
}

// MARK: - Memory Enums

enum MemoryType: String, Codable, CaseIterable {
    case quickMoment = "Photo Moment"
    case voiceMemory = "Voice Memory"
    case audioPhoto = "Audio Photo"
    case videoMessage = "Video Message"
    case milestone = "Milestone"
    case letterToFuture = "Letter to Future"
    case wisdomNote = "Wisdom Note"
    case familyRecipe = "Family Recipe"
    case storyTime = "Story Time"

    var icon: String {
        switch self {
        case .quickMoment: return "camera.fill"
        case .voiceMemory: return "waveform"
        case .audioPhoto: return "photo.on.rectangle"
        case .videoMessage: return "video.fill"
        case .milestone: return "star.fill"
        case .letterToFuture: return "envelope.fill"
        case .wisdomNote: return "lightbulb.fill"
        case .familyRecipe: return "fork.knife"
        case .storyTime: return "book.fill"
        }
    }

    var description: String {
        switch self {
        case .quickMoment: return "Photo + note"
        case .voiceMemory: return "Record audio message"
        case .audioPhoto: return "Photo with voice story"
        case .videoMessage: return "Record video greeting"
        case .milestone: return "Special achievement"
        case .letterToFuture: return "Letter for when they're older"
        case .wisdomNote: return "Life advice to pass down"
        case .familyRecipe: return "Recipe with photo"
        case .storyTime: return "Family story or tale"
        }
    }

    var accentColor: Color {
        switch self {
        case .quickMoment: return Color(hex: "FBBF24") // Amber/Gold
        case .voiceMemory: return Color(hex: "A78BFA") // Purple
        case .audioPhoto: return Color(hex: "F59E0B") // Amber
        case .videoMessage: return Color(hex: "60A5FA") // Blue
        case .milestone: return Color(hex: "34D399") // Green
        case .letterToFuture: return Color(hex: "F87171") // Red/Pink
        case .familyRecipe: return Color(hex: "FB923C") // Orange
        case .storyTime: return Color(hex: "2DD4BF") // Teal
        case .wisdomNote: return Color(hex: "818CF8") // Indigo
        }
    }
}

enum MemoryPrivacy: String, Codable, CaseIterable {
    case maybeDecide = "Maybe Decide"
    case shareNow = "Share Now"
    case vaultOnly = "Vault Only"
    case helloQueue = "Hello Queue"
}

// MARK: - Ancestor Enums

enum AncestorLineage: String, Codable, CaseIterable {
    case maternal = "Maternal"
    case paternal = "Paternal"
}

enum Gender: String, Codable, CaseIterable {
    case male = "Male"
    case female = "Female"
    case other = "Other"
}

enum FamilyRole: String, Codable, CaseIterable {
    // Parents (Generation 0)
    case mom = "Mom"
    case dad = "Dad"
    case stepMom = "Step-Mom"
    case stepDad = "Step-Dad"

    // Aunts & Uncles (Generation 0 - siblings of parents)
    case uncle = "Uncle"
    case aunt = "Aunt"
    case uncleInLaw = "Uncle-in-Law"
    case auntInLaw = "Aunt-in-Law"
    case stepUncle = "Step-Uncle"
    case stepAunt = "Step-Aunt"

    // Grandparents (Generation 1)
    case grandpa = "Grandpa"
    case grandma = "Grandma"
    case stepGrandpa = "Step-Grandpa"
    case stepGrandma = "Step-Grandma"

    // Great-Grandparents (Generation 2)
    case greatGrandpa = "Great-Grandpa"
    case greatGrandma = "Great-Grandma"

    // Great-Great-Grandparents (Generation 3)
    case greatGreatGrandpa = "Great-Great-Grandpa"
    case greatGreatGrandma = "Great-Great-Grandma"

    // Great-Aunts & Great-Uncles (Generation 1 - siblings of grandparents)
    case greatUncle = "Great-Uncle"
    case greatAunt = "Great-Aunt"
}

// MARK: - Pet Enums

enum PetType: String, Codable, CaseIterable {
    case dog = "Dog"
    case cat = "Cat"
    case bird = "Bird"
    case fish = "Fish"
    case rabbit = "Rabbit"
    case hamster = "Hamster"
    case other = "Other"

    var icon: String {
        switch self {
        case .dog: return "dog.fill"
        case .cat: return "cat.fill"
        case .bird: return "bird.fill"
        case .fish: return "fish.fill"
        case .rabbit: return "hare.fill"
        case .hamster: return "pawprint.fill"
        case .other: return "pawprint.fill"
        }
    }
}
