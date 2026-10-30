import LightTTSCore

let models = try ModelCatalog.load()
precondition(!models.isEmpty)
precondition(Set(models.map(\.id)).count == models.count)
for model in models {
    precondition(!model.id.isEmpty && !model.id.contains("/") && model.id != "." && model.id != "..")
}
print("Model catalog checks passed")
