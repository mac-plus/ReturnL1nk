import Foundation

// MARK: - Recipe Schema Models

struct Recipe: Codable, Identifiable {
    let id: UUID = UUID()
    let name: String
    let description: String?
    let sourceURL: URL?
    let imageURL: URL?
    let ingredients: [String]
    let instructions: [String]
    let yield: String?
    let totalTime: String?

    init(name: String,
         description: String?,
         sourceURL: URL?,
         imageURL: URL?,
         ingredients: [String],
         instructions: [String],
         yield: String?,
         totalTime: String?) {
        self.name = name
        self.description = description
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.ingredients = ingredients
        self.instructions = instructions
        self.yield = yield
        self.totalTime = totalTime
    }

    // Convenience initializer to map from raw schema payload
    init(from schema: RecipeSchema, sourceURL: URL?) {
        let resolvedIngredients = schema.recipeIngredient?.asStrings ?? []
        let resolvedInstructions = schema.recipeInstructions?.flattenedSteps ?? []

        self.init(
            name: schema.name ?? "Recipe",
            description: schema.description,
            sourceURL: sourceURL,
            imageURL: schema.image?.resolvedURL,
            ingredients: resolvedIngredients,
            instructions: resolvedInstructions,
            yield: schema.recipeYield?.asString,
            totalTime: schema.totalTime
        )
    }
}

// MARK: - Raw JSON-LD Schema

struct RecipeSchema: Codable {
    let context: String?
    let type: String?
    let name: String?
    let description: String?
    let image: SchemaImage?
    let recipeIngredient: SchemaIngredientList?
    let recipeInstructions: SchemaInstructionList?
    let recipeYield: SchemaYield?
    let totalTime: String?

    enum CodingKeys: String, CodingKey {
        case context = "@context"
        case type = "@type"
        case name
        case description
        case image
        case recipeIngredient
        case recipeInstructions
        case recipeYield
        case totalTime
    }
}

struct SchemaImage: Codable {
    let urlString: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: String].self) {
            urlString = dict["url"] ?? dict["@id"]
        } else if let array = try? container.decode([String].self) {
            urlString = array.first
        } else if let string = try? container.decode(String.self) {
            urlString = string
        } else {
            urlString = nil
        }
    }

    var resolvedURL: URL? { urlString.flatMap(URL.init(string:)) }
}

// MARK: - Ingredient Decoding

enum SchemaIngredientList: Codable {
    case single(String)
    case list([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            self = .list(array)
        } else if let string = try? container.decode(String.self) {
            self = .single(string)
        } else {
            self = .list([])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let value):
            try container.encode(value)
        case .list(let values):
            try container.encode(values)
        }
    }

    var asStrings: [String] {
        switch self {
        case .single(let value):
            return [value]
        case .list(let values):
            return values
        }
    }
}

// MARK: - Instruction Decoding

enum SchemaInstructionList: Codable {
    case text(String)
    case steps([SchemaInstructionStep])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let steps = try? container.decode([SchemaInstructionStep].self) {
            self = .steps(steps)
        } else if let strings = try? container.decode([String].self) {
            self = .steps(strings.map { SchemaInstructionStep(text: $0) })
        } else if let string = try? container.decode(String.self) {
            self = .text(string)
        } else {
            self = .steps([])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .steps(let steps):
            try container.encode(steps)
        }
    }

    var flattenedSteps: [String] {
        switch self {
        case .text(let text):
            return [text]
        case .steps(let steps):
            return steps.compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
    }
}

struct SchemaInstructionStep: Codable {
    let type: String?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case type = "@type"
        case text
    }
}

// MARK: - Yield decoding

enum SchemaYield: Codable {
    case text(String)
    case list([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([String].self) {
            self = .list(list)
        } else if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .list([])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .list(let list):
            try container.encode(list)
        }
    }

    var asString: String? {
        switch self {
        case .text(let text):
            return text
        case .list(let list):
            return list.joined(separator: ", ")
        }
    }
}

// MARK: - Formatter helpers

extension Recipe {
    var markdown: String {
        var lines: [String] = []
        lines.append("# \(name)")
        if let sourceURL { lines.append("\n\(sourceURL.absoluteString)") }
        lines.append("\n## Ingredients")
        ingredients.forEach { lines.append("- \($0)") }
        lines.append("\n## Instructions")
        for (index, step) in instructions.enumerated() {
            lines.append("\(index + 1). \(step)")
        }
        if let yield { lines.append("\nYield: \(yield)") }
        if let totalTime { lines.append("Total time: \(totalTime)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Helpers for parsing from JSON-LD blobs

struct RecipeExtractor {
    static func decodeRecipes(from data: Data, sourceURL: URL?) throws -> [Recipe] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Attempt direct RecipeSchema first
        if let recipe = try? decoder.decode(RecipeSchema.self, from: data), recipe.typeMatchesRecipe {
            return [Recipe(from: recipe, sourceURL: sourceURL)]
        }

        // Attempt graph array
        if let graphPayload = try? decoder.decode(GraphContainer.self, from: data) {
            let recipes = graphPayload.graph
                .filter { $0.typeMatchesRecipe }
                .map { Recipe(from: $0, sourceURL: sourceURL) }
            if !recipes.isEmpty { return recipes }
        }

        // Attempt array of recipes
        if let recipeArray = try? decoder.decode([RecipeSchema].self, from: data) {
            let recipes = recipeArray.filter { $0.typeMatchesRecipe }.map { Recipe(from: $0, sourceURL: sourceURL) }
            if !recipes.isEmpty { return recipes }
        }

        throw NSError(domain: "RecipeExtractor", code: -1, userInfo: [NSLocalizedDescriptionKey: "No recipe JSON-LD found"])
    }
}

struct GraphContainer: Codable {
    let context: String?
    let graph: [RecipeSchema]

    enum CodingKeys: String, CodingKey {
        case context = "@context"
        case graph = "@graph"
    }
}

private extension RecipeSchema {
    var typeMatchesRecipe: Bool {
        guard let type = type?.lowercased() else { return false }
        return type == "recipe" || type.contains("recipe")
    }
}
