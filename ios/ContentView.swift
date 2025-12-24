import SwiftUI

struct ContentView: View {
    @State private var urlString: String = ""
    @State private var recipes: [Recipe] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Paste recipe URL", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                HStack {
                    Button("Fetch Recipe") { fetch() }
                        .buttonStyle(.borderedProminent)
                    Button("Clear") { recipes.removeAll() }
                        .buttonStyle(.bordered)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }

                List(recipes) { recipe in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipe.name)
                            .font(.headline)
                        if let url = recipe.sourceURL {
                            Text(url.absoluteString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(recipe.markdown)
                            .font(.footnote)
                            .lineLimit(6)
                    }
                }
            }
            .padding()
            .navigationTitle("Recipe Extractor")
        }
    }

    private func fetch() {
        guard let url = URL(string: urlString) else {
            errorMessage = "Please enter a valid URL"
            return
        }
        errorMessage = nil

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let html = String(data: data, encoding: .utf8),
                      let recipeJSON = extractJSONLDPayload(from: html) else {
                    errorMessage = "No recipe JSON-LD found"
                    return
                }
                let recipes = try RecipeExtractor.decodeRecipes(from: recipeJSON, sourceURL: url)
                self.recipes = recipes
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func extractJSONLDPayload(from html: String) -> Data? {
        let pattern = "<script[^>]*type=\\\"application/ld\\+json\\\"[^>]*>([\\s\\S]*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        guard let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) else { return nil }
        let range = match.range(at: 1)
        guard let swiftRange = Range(range, in: html) else { return nil }
        let jsonString = String(html[swiftRange])
        return jsonString.data(using: .utf8)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
