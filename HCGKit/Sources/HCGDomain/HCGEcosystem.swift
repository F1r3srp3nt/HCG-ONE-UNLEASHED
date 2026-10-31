import Foundation

// Product catalog adapted from HCG-One@b4f0e29: ios-hcg/HCGONE/Models/Company.swift
// (HCGProductRegistry). Statuses are maintained by HCG; nothing here is
// fetched from a server, and availability is never invented.

public struct HCGProduct: Identifiable, Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        case available
        case inDevelopment

        public var label: String {
            switch self {
            case .available: "Available"
            case .inDevelopment: "In development"
            }
        }
    }

    public let id: String
    public let name: String
    public let summary: String
    public let platforms: String
    public let status: Status
}

public enum HCGEcosystem {
    public static let companyName = "Hakmi Capital Group"
    public static let productName = "HCG ONE: UNLEASHED"

    /// The HCG product family as published in HCG ONE. Updated for this app.
    public static let products: [HCGProduct] = [
        HCGProduct(
            id: "hcg-one-unleashed", name: "HCG ONE: UNLEASHED",
            summary: "The native macOS edition of HCG ONE — this app. Currently in its first development build.",
            platforms: "macOS", status: .inDevelopment),
        HCGProduct(
            id: "hcg-one", name: "HCG ONE",
            summary: "The HCG ONE mobile platform: discover the company, request services and manage your HCG account.",
            platforms: "iPhone · iPad", status: .inDevelopment),
        HCGProduct(
            id: "asset-index", name: "Hakmi Asset Index",
            summary: "Asset tracking, collection management and valuation research for alternative assets.",
            platforms: "Planned", status: .inDevelopment),
        HCGProduct(
            id: "signature-studios", name: "Hakmi Signature Studios",
            summary: "Signature creation, handwriting practice and educational exercises.",
            platforms: "Planned", status: .inDevelopment),
        HCGProduct(
            id: "trader-mission", name: "Trader Mission",
            summary: "Trading-related education and simulated markets.",
            platforms: "Planned", status: .inDevelopment),
        HCGProduct(
            id: "hcg-erp", name: "HCG Enterprise",
            summary: "HCG's enterprise system for projects, clients, employees and operations.",
            platforms: "Web", status: .inDevelopment),
    ]
}
