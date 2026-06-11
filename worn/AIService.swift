//
//  AIService.swift
//  worn
//

import Foundation
import UIKit
import SwiftData
// MARK: - Tag structure that comes back from the AI

struct ItemTags: Codable {
    let name: String
    let category: String
    let colors: [String]
    let formality: Int
    let vibeTags: [String]
    let occasionTags: [String]
    let weatherTags: [String]    // ← changed from seasonTags
}
// MARK: - AI Service

enum AIServiceError: Error {
    case missingAPIKey
    case invalidResponse
    case imageEncodingFailed
    case decodingFailed(String)
}

struct AIService {
    
    /// Reads the API key from Secrets.plist
    private static var apiKey: String {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let key = plist["AnthropicAPIKey"] as? String else {
            return ""
        }
        return key
    }
    
    /// Sends an image to Claude and gets back structured tags
    static func tagImage(_ image: UIImage) async throws -> ItemTags {
        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        
        // Resize the image so we don't send 5MB. ~1024px on longest side is plenty for tagging.
        let resized = resize(image, maxDimension: 1024)
        guard let imageData = resized.jpegData(compressionQuality: 0.8) else {
            throw AIServiceError.imageEncodingFailed
        }
        let base64Image = imageData.base64EncodedString()
        
        // The prompt: tell Claude exactly what tags we want and to respond ONLY with JSON.
        let prompt = """
        You are a fashion-savvy assistant tagging a clothing item for a digital closet app.

        Analyze the clothing item in the image and return a JSON object (and ONLY JSON, no extra text) with these exact fields:
        - name: a short descriptive name (e.g. "black silk camisole", "cream knit cardigan")
        - category: one of "top", "bottom", "dress", "outerwear", "shoes", "accessory"
        - colors: array of 1-3 dominant colors as simple strings (e.g. ["black", "cream"])
        - formality: integer 1-6 indicating where the item belongs:
            1 = lounge (pajamas, sweatpants, anything you wouldn't leave the house in)
            2 = casual (everyday wear, jeans, tees, hoodies, sneakers)
            3 = dressy / going out (date night, dinner, parties — includes sheer, lace, satin, silky, flowy, body-con, or anything with a "going out" feel even if technically fancy)
            4 = business / professional (structured fabrics, blazers, oxford shirts, slacks, modest necklines, things appropriate for a meeting or office)
            5 = formal (black-tie, gala, wedding-guest formal, floor-length gowns, tuxedos)

            IMPORTANT distinctions:
            - Sheer, lace, satin, silky, or flowy materials are almost never business (4). Default them to dressy (3) unless extremely conservative.
            - Date night unless speficied is dressy but more conservative thna going out, going out is show stopping.
            - Going out is usually for darker colored items unless that items is particularly dressy, intricate, risque, sheer, etc.
            - Body-con, mini, cropped, low-cut, or "going out" silhouettes are dressy (3), not business (4).
            - Business (4) requires structured fabrics AND a modest, professional silhouette.
            - When in doubt between 3 and 4, ask: "Could this be worn to a corporate office without comment?" If no, it's 3.
        - vibeTags: array of 1-4 aesthetic tags from this list: "coquette", "old money", "streetwear", "preppy", "grunge", "clean girl", "boho", "minimalist", "y2k", "edgy", "romantic", "sporty", "going out"
        - occasionTags: array of 1-3 from: "work", "date", "party", "formal", "casual", "athletic", "loungewear", "vacation"
        - weatherTags: array of 1-3 from: "spring", "summer", "fall", "winter", "warm weather", "cold weather", "transitional"

        Respond with ONLY the JSON object, no markdown code blocks, no explanation.
        """
        
        // Build the request body for Anthropic's Messages API
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-5",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]
        
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Parse Claude's response — text lives at content[0].text
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            // Print the raw response for debugging
            if let raw = String(data: data, encoding: .utf8) {
                print("AI raw response: \(raw)")
            }
            throw AIServiceError.invalidResponse
        }
        
        // Strip any accidental markdown wrapping
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw AIServiceError.decodingFailed("Could not convert text to data")
        }
        
        do {
            let tags = try JSONDecoder().decode(ItemTags.self, from: jsonData)
            return tags
        } catch {
            print("Decode error: \(error)")
            print("Cleaned text was: \(cleaned)")
            throw AIServiceError.decodingFailed(error.localizedDescription)
        }
    }
    // MARK: - Vibe Search

    struct VibeSearchResult: Codable {
        let itemIds: [String]
        let reasoning: String
    }

    /// Returns pieces from the closet that fit the vibe.
    /// Does NOT try to construct full outfits — just surfaces relevant items.
    static func searchByVibe(query: String, items: [Item]) async throws -> VibeSearchResult {
        guard !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        
        let itemSummaries = items.map { item -> String in
            let id = item.persistentModelID.hashValue.description
            let parts: [String] = [
                "ID: \(id)",
                "Name: \(item.name)",
                "Category: \(item.category)",
                "Colors: \(item.colors.joined(separator: ", "))",
                "Formality: \(item.formality)/5",
                "Vibes: \(item.vibeTags.joined(separator: ", "))",
                "Occasions: \(item.occasionTags.joined(separator: ", "))",
                "Weather: \(item.weatherTags.joined(separator: ", "))",
                "Worn: \(item.wearCount) times"
            ]
            return parts.joined(separator: " | ")
        }.joined(separator: "\n")
        
        let prompt = """
        You help someone pick clothing pieces from their closet for a given vibe.
        
        Your job is NOT to construct full outfits. Just surface individual pieces that fit the vibe — the user will mix and match themselves.
        
        THEIR CLOSET:
        \(itemSummaries)
        
        THEIR REQUEST: "\(query)"
        
        Pick up to 15 individual items that fit the vibe. Include a variety of categories (tops, bottoms, dresses, outerwear etc.) so the user has real options to choose from.
        
        IMPORTANT RANKING RULES:
        1. STRONGLY prefer items the user has worn FEWER times — this app exists to resurface forgotten pieces. An item worn 0-1 times should rank above an equally-fitting item worn 10+ times.
        2. Only include items whose tags genuinely match. Don't stretch to fill 15 slots — if only 3 things fit, return 3.
        3. Match on the actual vibe components: formality, occasion, weather, and aesthetic. If they say "warm night dinner date," prefer dressy + warm weather + romantic/going-out vibes.
        4. Order results by best-fit first.
        
        Respond with ONLY this JSON (no markdown, no extra text):
        {
          "itemIds": ["id1", "id2", ...],
          "reasoning": "1-2 sentences on why these pieces fit, mentioning if any are pieces they haven't worn recently"
        }
        """
        
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-5",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            if let raw = String(data: data, encoding: .utf8) {
                print("Vibe search raw response: \(raw)")
            }
            throw AIServiceError.invalidResponse
        }
        
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw AIServiceError.decodingFailed("Could not convert text to data")
        }
        
        do {
            return try JSONDecoder().decode(VibeSearchResult.self, from: jsonData)
        } catch {
            print("Vibe search decode error: \(error)")
            print("Cleaned text was: \(cleaned)")
            throw AIServiceError.decodingFailed(error.localizedDescription)
        }
    }
    
    /// Resize image so we're not uploading huge files
    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        if scale >= 1.0 { return image }
        
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}//
//  AIService.swift
//  worn
//
//  Created by min rungsinaporn on 1/6/2569 BE.
//

