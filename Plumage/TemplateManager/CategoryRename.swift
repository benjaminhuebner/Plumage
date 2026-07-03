// Inline-rename session for a sidebar category header. `id` is the category id;
// `name` is bound by the header's `TextField`.
struct CategoryRename: Identifiable, Equatable {
    let id: String
    var name: String
}
