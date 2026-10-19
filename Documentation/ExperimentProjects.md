# Grammar-REPL experiment projects

An experiment project is a deterministic, path-independent collection of named
Grammar-REPL experiment documents. It is designed for a study rather than a
single run: accepted and rejected inputs, ambiguity examples, precedence
variants, and semantic mappings can live together while every entry remains an
independently replayable artifact.

## Format and identity

Project schema 1 stores a name, optional description, canonical entry list,
producer identity, and FNV-1a fingerprint. Entries are sorted by identifier and
tags are sorted and deduplicated. Duplicate identifiers, non-canonical entry
ordering or tags, modified nested experiments, and fingerprint changes fail
before replay.

The project fingerprint includes every nested experiment. It deliberately does
not include file paths, timestamps, host information, or Swift's randomized
`Hasher`, so the same project has the same identity on every supported host.

Nested experiments retain their original schema and fingerprint. Existing
artifacts can therefore be imported without rewriting their evidence or
changing their identities.

## Interactive workflow

```text
:experiment project-create expression-study.json "Expression study"
:compare "42"
:experiment project-add expression-study.json integer
:compare "1 PLUS 2"
:experiment project-add expression-study.json addition
:experiment show expression-study.json
:experiment verify expression-study.json
```

`project-add` captures the current comparison, including precedence,
resolution policy, Compiler semantics, parser contracts, derivation identities,
and semantic evidence. It refuses duplicate identifiers. `project-create`
refuses to replace an existing file.

## Non-interactive workflow

Existing standalone artifacts can be assembled without rerunning them:

```sh
swift run grammar-repl-experiment project-create study.json "Expression study"
swift run grammar-repl-experiment project-add study.json integer integer.json
swift run grammar-repl-experiment show study.json
swift run grammar-repl-experiment verify study.json
```

Verification exits unsuccessfully if any nested experiment diverges. The JSON
format is described by `Schemas/ExperimentProject.schema.json`; the Swift
decoder additionally validates canonical ordering, nested experiment
fingerprints, precedence, and semantic evidence.
