// `config` lands at the project root (`.swift-format`), not under `.claude/` like the
// others. `skill` stays decodable for legacy manifests but is no longer written —
// a component's skills are scope-owned loose folders under `components/<id>/skills/`.
nonisolated enum SharedComponentKind: String, Codable, Hashable, Sendable, CaseIterable {
    case layer
    case hook
    case skill
    case config

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let kind = Self(rawValue: raw) else {
            throw UnknownKindError(field: "component file kind", value: raw)
        }
        self = kind
    }
}

// One file a component contributes, tagged with the kind that decides where it lands
// in a scaffolded project (`layer` → CLAUDE.md, `hook` → hooks/<name>.sh, …). A single
// component may mix kinds — e.g. a Swift bundle carrying a CLAUDE.md layer *and* its
// tooling hooks.
nonisolated struct ComponentFile: Codable, Hashable, Sendable {
    let kind: SharedComponentKind
    let name: String

    // The override-store path this file's bytes resolve to. `hookFileName` maps a
    // hook's base name to its real on-disk filename (extension included).
    func storePath(hookFileName: (String) -> String) -> String {
        switch kind {
        case .layer: ScaffoldOverrides.layerRelativePath(name)
        case .hook: "hooks/\(hookFileName(name))"
        case .skill: "skills/\(name)/SKILL.md"
        case .config: "configs/\(name)"
        }
    }
}

// The middle tier: a reusable building block included in a selectable subset of
// templates. `memberTemplateIDs` is the explicit per-template membership; `order`
// fixes the concatenation position so composed layers stay byte-stable.
nonisolated struct SharedComponent: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var name: String
    var files: [ComponentFile]
    var order: Int
    var memberTemplateIDs: Set<String>

    func isMember(_ templateID: String) -> Bool { memberTemplateIDs.contains(templateID) }

    // The names of this component's files of a given kind, in declaration order — the
    // effective resolver concatenates layers and hooks from here.
    func files(ofKind kind: SharedComponentKind) -> [String] {
        files.filter { $0.kind == kind }.map(\.name)
    }

    init(
        id: String, name: String, files: [ComponentFile], order: Int,
        memberTemplateIDs: Set<String>
    ) {
        self.id = id
        self.name = name
        self.files = files
        self.order = order
        self.memberTemplateIDs = memberTemplateIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, files, order, memberTemplateIDs
    }

    // Branch is shape-based (presence of the legacy top-level `kind` key), not
    // decode-success-based: a `try?` on `files` would read an empty `[]` as the current
    // shape and silently drop a legacy `kind`, and would mask a real decoding error.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decode(Int.self, forKey: .order)
        memberTemplateIDs = try container.decode(Set<String>.self, forKey: .memberTemplateIDs)
        if container.contains(.kind) {
            let kind = try container.decode(SharedComponentKind.self, forKey: .kind)
            let names = try container.decode([String].self, forKey: .files)
            files = names.map { ComponentFile(kind: kind, name: $0) }
        } else {
            files = try container.decode([ComponentFile].self, forKey: .files)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(files, forKey: .files)
        try container.encode(order, forKey: .order)
        try container.encode(memberTemplateIDs, forKey: .memberTemplateIDs)
    }
}
