import UIKit
import Social
import SwiftUI

final class ShareViewController: SLComposeServiceViewController {
    private var extractedRecipe: Recipe?

    override func isContentValid() -> Bool {
        return true
    }

    override func presentationAnimationDidFinish() {
        super.presentationAnimationDidFinish()
        extractURLFromContext()
    }

    override func didSelectPost() {
        guard let recipe = extractedRecipe else {
            cancel()
            return
        }
        let markdown = recipe.markdown
        UIPasteboard.general.string = markdown
        openNotesApp()
        completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    private func extractURLFromContext() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem else { return }
        guard let provider = extensionItem.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier("public.url") }) else { return }

        provider.loadItem(forTypeIdentifier: "public.url", options: nil) { [weak self] (item, error) in
            guard let self else { return }
            if let error { self.cancelRequest(with: error) ; return }
            if let url = item as? URL {
                self.fetchJSONLD(from: url)
            } else if let dict = item as? NSDictionary, let url = dict["URL"] as? URL {
                self.fetchJSONLD(from: url)
            }
        }
    }

    private func fetchJSONLD(from url: URL) {
        // Inject RecipeExtractor.js into the webpage via JavaScript
        let request = URLRequest(url: url)
        let session = URLSession(configuration: .ephemeral)

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error { self.cancelRequest(with: error); return }
            guard let data else { self.cancelRequest(with: NSError(domain: "ShareViewController", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])) ; return }

            // Attempt to parse raw HTML to locate script tags
            guard let html = String(data: data, encoding: .utf8) else {
                self.cancelRequest(with: NSError(domain: "ShareViewController", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unable to decode HTML"]))
                return
            }

            guard let recipeJSON = self.extractJSONLDPayload(from: html) else {
                self.cancelRequest(with: NSError(domain: "ShareViewController", code: -4, userInfo: [NSLocalizedDescriptionKey: "No recipe JSON-LD found"]))
                return
            }

            do {
                let recipes = try RecipeExtractor.decodeRecipes(from: recipeJSON, sourceURL: url)
                if let recipe = recipes.first {
                    self.extractedRecipe = recipe
                    DispatchQueue.main.async {
                        self.presentSwiftUIView(with: recipe)
                    }
                }
            } catch {
                self.cancelRequest(with: error)
            }
        }

        task.resume()
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

    private func presentSwiftUIView(with recipe: Recipe) {
        let hosting = UIHostingController(rootView: ShareRecipeView(recipe: recipe))
        hosting.modalPresentationStyle = .formSheet
        present(hosting, animated: true)
    }

    private func openNotesApp() {
        guard let notesURL = URL(string: "mobilenotes://") else { return }
        _ = openURL(notesURL)
    }

    private func cancelRequest(with error: Error) {
        let alert = UIAlertController(title: "Recipe extraction failed", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel) { _ in
            self.cancel()
        })
        DispatchQueue.main.async {
            self.present(alert, animated: true)
        }
    }
}

// MARK: - SwiftUI Helper View

struct ShareRecipeView: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(recipe.name)
                .font(.title)
                .bold()
            if let description = recipe.description {
                Text(description)
                    .font(.subheadline)
            }
            ScrollView {
                Text(recipe.markdown)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Copy to Clipboard") {
                    UIPasteboard.general.string = recipe.markdown
                }
                Button("Open in Notes") {
                    UIPasteboard.general.string = recipe.markdown
                    if let notesURL = URL(string: "mobilenotes://") {
                        UIApplication.shared.open(notesURL)
                    }
                }
            }
        }
        .padding()
    }
}
