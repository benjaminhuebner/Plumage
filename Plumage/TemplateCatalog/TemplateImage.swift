// Visual marker for a template/category in the Template Manager. Predefined
// entries use SF Symbols; custom entries may instead reference an imported image
// file by a path relative to the override namespace (`template-images/<id>.<ext>`),
// so the image travels with the template's other override files.
nonisolated enum TemplateImage: Codable, Hashable, Sendable {
    case symbol(String)
    case file(String)
}
