# Grammar REPL

`grammar-repl` is a small, terminal-first workbench for exploring context-free
grammars and the parsers generated from them. It turns the Grammar and Parser
packages from a collection of library APIs into an interactive environment in
which a grammar author can ask questions, try input, inspect results, modify the
grammar, and immediately try again.

The REPL is deliberately modest. It is not an editor, a compiler frontend, or a
full-screen terminal application. It is an interactive client of the existing
grammar-analysis and generalized-parser facilities. This makes the first version
useful without duplicating those facilities, and provides a foundation for later
LR conflict inspection, error recovery experiments, tracing, and graphical
grammar artifacts.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)  
[![Platforms](https://img.shields.io/badge/platforms-macOS%2011%20%7C%20iOS%2014-blue.svg)](https://developer.apple.com/swift/)  
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)  

---

## Why a grammar REPL?

Parser generators are often experienced as black boxes. A grammar goes in and a
parser comes out, but questions that arise during grammar development can be hard
to answer:

- What can begin this nonterminal?
- What can legally follow it?
- Which production will an LL(1) parser choose for this lookahead?
- Why is the grammar not LL(1)?
- Does the grammar accept this particular sentence?
- Do different parsing algorithms produce the same result?
- Is an accepted sentence ambiguous?
- What does the resulting concrete syntax tree look like?

The REPL makes these questions part of a short edit–reload–inspect–parse loop:

```text
edit grammar
    ↓
:reload
    ↓
:check / :first / :follow / :predict
    ↓
:parse sample input
    ↓
:tree
```

The long-term goal is a grammar laboratory in which deterministic and
generalized parsing algorithms can be compared through a common interaction
model. The present implementation establishes that interaction model using the
public APIs already available in the repository's dependencies.

## Current capabilities

The prototype currently supports:

- loading `.bnf`, `.ebnf`, `.wsn`, and `.gen` grammar files;
- reloading the active grammar after it is edited;
- displaying the normalized grammar;
- displaying FIRST and FOLLOW sets;
- calculating and displaying PREDICT sets for individual productions;
- detecting pairwise LL(1) PREDICT-set conflicts;
- selecting Earley, CYK, RNGLR, LR(0), SLR, LALR, or canonical LR(1);
- inspecting generated LR states, transitions, ACTION/GOTO tables, conflicts,
  and shortest conflict witnesses;
- structured parser outcomes and bounded local repair in deterministic LR modes;
- ASCII railroad diagrams plus DOT renderers for LR automata, LR states,
  conflict explanations, and retained parse trees;
- persistent interactive history and semantic tab completion;
- stable semantic identities for LR productions, items, states, transitions,
  and conflicts;
- opt-in structured LR parser tracing with shift, reduce, error, recovery, and
  acceptance events;
- parsing sample input without leaving the session;
- retaining every derivation returned by the selected parser;
- displaying a selected parse tree with source lexemes at its leaves;
- showing the current session settings;
- embedded `%left`, `%right`, and `%nonassoc` precedence declarations;
- schema-versioned JSON snapshots for workbench and editor clients;
- conflict witness minimization and relevant-production slices;
- generation benchmark/stress instrumentation;
- an observable incremental LR parsing prototype;
- a transport-neutral language-server document service.

The prototype does **not** yet implement:

- LL(1) runtime parsing through the `LL-Parsing` package;
- resumable LR stack checkpoints (edited input is incrementally analyzed and
  then fully validated);
- JSON-RPC process framing for a standalone Language Server Protocol executable.

These are planned extensions, not hidden or incomplete commands.

## Building and running

From the repository root:

```sh
swift build --product grammar-repl
swift run grammar-repl
```

The REPL starts with an empty session:

```text
Grammar REPL — type :help for commands
grammar>
```

Commands begin with a colon. A nonempty line without a colon is interpreted as
sample input and is equivalent to `:parse <line>`.

Exit with `:quit`, `:exit`, `:q`, or end-of-file (`Control-D` in a typical
terminal).

## Quick tour

The repository includes a small arithmetic grammar. Because BNF files do not
carry their own start declaration, give the start nonterminal after the path:

```text
grammar> :load Examples/arithmetic.bnf program
Loaded arithmetic.bnf: 20 productions, start <program>.
```

Inspect its LL(1) properties:

```text
grammar> :first expression
FIRST(<expression>) = {"(", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}

grammar> :follow expression
FOLLOW(<expression>) = {")", "+", "-", ";"}

grammar> :predict expression
[1] expression --> expression "+" term
    PREDICT = {"(", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}
[2] expression --> expression "-" term
    PREDICT = {"(", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}
[3] expression --> term
    PREDICT = {"(", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}
```

The alternatives have overlapping prediction sets, so the grammar is not
LL(1):

```text
grammar> :check
Grammar: 20 productions, 6 nonterminals, 18 terminals.
Found 6 LL(1) prediction conflicts:
[1] <expression> on {"(", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}
    expression --> expression "+" term
    expression --> expression "-" term
...
Selected runtime parser: earley.
```

This does not mean the grammar is invalid. It means that one token of lookahead
cannot uniquely select an alternative. A generalized parser can still parse it:

```text
grammar> :parser earley
Parser set to earley.

grammar> :parse print 1 + 2 * 3;
Accepted by earley: 1 derivation.

grammar> :tree
program
└── statement
    ├── "print"
    ├── expression
    ...
    └── ";"
```

Edit `Examples/arithmetic.bnf` in another window, then reload it without
re-entering its path or start symbol:

```text
grammar> :reload
Loaded arithmetic.bnf: 20 productions, start <program>.
```

## Command reference

### `:load <file> [start]`

Loads a grammar and replaces the active session grammar.

```text
:load Examples/arithmetic.bnf program
:load Examples/language.gen
:load "/path/containing spaces/language.ebnf" program
```

The notation is inferred from the filename extension:

| Extension | Grammar initializer    | Start argument        |
| --------- | ---------------------- | --------------------- |
| `.bnf`    | `Grammar(bnf:start:)`  | required              |
| `.ebnf`   | `Grammar(ebnf:start:)` | required              |
| `.wsn`    | `Grammar(wsn:start:)`  | required              |
| `.gen`    | `Grammar(gen:)`        | read from the grammar |

Loading a grammar clears the previous input and parse trees. This prevents a
tree produced by an old grammar from being presented as a result of the newly
loaded one.

Paths may be enclosed in single or double quotes. The prototype intentionally
implements only the quoting needed for paths; it is not a complete shell
language and does not perform environment-variable, wildcard, or escape
expansion.

### `:reload`

Reloads the current grammar from its original path with the same notation and
start symbol. A successful reload clears the last input and parse trees.

This command is the center of the intended workflow: edit the grammar in an
editor, return to the REPL, and run `:reload` followed by the desired analysis
or sample parse.

### `:grammar`

Displays the loaded `Grammar` value. This is the normalized grammar consumed by
the parser packages and can differ structurally from the original EBNF or WSN
source after notation lowering.

### `:parser [earley|cyk|rnglr|lr0|slr|lalr|lr1]`

With no valid argument, displays the current parser and available choices:

```text
grammar> :parser
Parser: earley. Available: earley, cyk, rnglr.
```

With an argument, selects the parser used by subsequent `:parse` commands:

```text
grammar> :parser rnglr
Parser set to rnglr.
```

Changing the parser clears retained trees because they were produced by a
different parsing algorithm. It retains the grammar and last input.

The selected algorithms are generalized parsers. Consequently, an LL(1)
conflict reported by `:check` does not prevent `:parse` from succeeding.

### `:check`

Displays a compact grammar summary and checks whether the alternatives of every
nonterminal have disjoint PREDICT sets.

For every pair of productions `A → α` and `A → β`, the command calculates:

```text
PREDICT(A → α) ∩ PREDICT(A → β)
```

An empty intersection means those two alternatives can be distinguished with
one token of lookahead. A nonempty intersection is reported as an LL(1)
conflict, including the nonterminal, overlapping lookaheads, and both
productions.

When an LR parser is selected, `:check` also generates and caches its automaton
and reports state and LR-conflict counts.

### `:conflicts`, `:state`, `:explain`, and `:replay`

`:conflicts` lists shared structured LL conflicts in generalized-parser modes,
or LR shift/reduce and reduce/reduce cells in LR modes. Use `:conflicts
unresolved`, `:conflicts resolved`, or `:conflicts all` to filter the LR view;
displayed numbers remain stable across filters. `:state N` renders
the items and outgoing transitions of state `N`. `:explain N` shows the
one-based LR conflict `N`, its stable identity, and the shortest terminal
witness reaching the conflict lookahead. Each competing candidate then shows:

- the proposed shift, reduction, or accept action;
- why the generator proposed it (terminal transition, LR(0), SLR/FOLLOW,
  LR(1)/LALR item lookahead, or augmented start);
- the exact originating LR item;
- stable item and candidate identities;
- the complete conflicting state as context.

The explanation also identifies the selected action, its stable decision ID,
its resolved/unresolved status, and the explicit policy used to select it.
Fallback accept, shift, and generation-order choices remain unresolved and
continue to block strict deterministic parsing.

Declare interactive precedence levels with a positive or negative integer;
larger numbers bind more tightly:

```text
:precedence 1 left + -
:precedence 2 left * /
:precedence 3 right ^
:precedence 4 nonassoc < >
:precedence             # list declarations
:precedence clear
```

Equal-precedence shift/reduce cells select reduce for `left`, shift for
`right`, and an error ACTION cell for `nonassoc`. Precedence declarations are
specific to the loaded grammar and are cleared by `:load` or `:reload`.

The same declarations can live at the beginning of BNF, EBNF, WSN, or GEN
source. Declaration order establishes increasing precedence:

```bnf
%left "+" "-"
%left "*" "/"
%right "^"
%nonassoc "<" ">"

<expression> ::= <expression> "+" <expression> | "id"
```

Directive lines are replaced with blank lines before the notation parser runs,
so subsequent source line numbers are preserved. Interactive `:precedence`
commands may replace levels for the current session.

For conflicts not covered by precedence, select an explicit session policy:

```text
:resolution shift
:resolution reduce
:resolution reject
:resolution          # show the current policy
:resolution clear
```

Shift and reduce policies choose a matching candidate. `reject` deliberately
installs an error ACTION cell. These choices are marked resolved and retain the
policy name and explanation in `:explain`; clearing the policy restores the
unresolved fallback behavior. Declared precedence takes priority over the
general session policy. Policy changes invalidate cached automata.

`:replay N` executes conflict `N`'s shortest terminal witness against the
generated ACTION and GOTO decisions. It prints each shift and reduction with
the parser-state stack, then stops immediately before applying the conflicted
cell and reports the selected action and policy. If a generated witness cannot
reach its advertised cell, replay returns a structured failure instead of
silently producing a misleading trace.

`:replay N all` additionally forces each competing action from the identical
stack and token position, then follows generated decisions until acceptance,
rejection, or the replay bound. Each branch indicates whether it was selected
by the active resolution policy and reports its independent outcome.

`:decisions` lists every generated ACTION decision; `:decisions N` restricts
the view to state `N`. Entries show the selected action or error cell,
resolved/unresolved status, policy explanation, origin count, and stable ID.

The artifact retains origins for every ACTION cell, including multiple items
that independently justify the same selected action. Only distinct competing
actions are classified as a conflict.

Conflicted LR grammars still produce an inspectable generation artifact. The
deterministic runtime accepts intentionally resolved tables and rejects tables
that retain any unresolved conflict. In LR-Parsing itself, `conflicts` contains
only unresolved conflicts, while `resolvedConflicts` and `resolvedDecisions`
hold intentional decisions; `allConflicts` provides the combined sorted view
used for stable REPL numbering.

### `:first <nonterminal>`

Displays the terminals that may begin a string derived from the named
nonterminal:

```text
:first expression
:first <expression>
```

Angle brackets are optional. Nonterminal lookup uses the exact name after
trimming angle brackets and surrounding spaces.

### `:follow <nonterminal>`

Displays terminals that may occur immediately after the named nonterminal in a
sentential form. The grammar end-of-input marker is included where appropriate.

### `:predict <nonterminal>`

Displays every production for the nonterminal and the lookaheads on which an
LL(1) parser would select it.

For `A → α`, the REPL calculates:

```text
PREDICT(A → α) = FIRST(α) − {ε}
```

If `α` is nullable, it additionally includes `FOLLOW(A)`:

```text
PREDICT(A → α) = (FIRST(α) − {ε}) ∪ FOLLOW(A)
```

The implementation uses `Grammar.firstAndFollow()` and
`Grammar.first(of:using:)`; it does not maintain a second independent FIRST or
FOLLOW implementation.

### `:parse <input>`

Runs the selected parser against sample input and retains all returned parse
trees:

```text
:parse print 1 + 2 * 3;
:parse "print 1 + 2 * 3;"
```

The outer matching quotes in the second form are command delimiters and are not
part of the sample input. A plain line is more convenient for most input:

```text
grammar> print 1 + 2 * 3;
Accepted by earley: 1 derivation.
```

On success, the REPL reports the number of derivations. On failure, the parser's
current error description is displayed and the session remains active.

The runtime dispatch is direct:

```swift
switch selectedParser {
case .earley:
    EarleyParser(grammar: grammar).allSyntaxTrees(for: input)
case .cyk:
    CYKParser(grammar: grammar).allSyntaxTrees(for: input)
case .rnglr:
    RNGLRParser(grammar: grammar).allSyntaxTrees(for: input)
}
```

This is intentionally a thin adapter. Tokenization, recognition, forest
construction, and tree enumeration remain responsibilities of their respective
packages.

### `:tree [number]`

Displays a parse tree retained by the most recent successful `:parse`. Tree
numbers are one-based:

```text
:tree       # first derivation
:tree 1     # first derivation
:tree 2     # second derivation
```

The shared `ParseTree` stores leaf ranges into the original input. The REPL's
tree renderer resolves each range back to its source lexeme, so a leaf is shown
as `"print"` rather than as an internal `String.Index` range.

### `:settings`

Displays the active grammar path, selected parser, and last input:

```text
Grammar: /absolute/path/to/arithmetic.bnf
Parser: earley
Last input: print 1 + 2 * 3;
```

### `:trace` and `:identity`

LR runtime tracing is opt-in and retained with the last LR parse:

```text
:parser lalr
:trace on
:parse id + id
:trace          # show the complete retained trace
:trace 10       # show the last ten events
:trace clear
:trace off
```

Trace events contain the token position, lookahead, stack snapshot, numeric
state index, stable state identity, target state, and reduction production
identity where applicable. Errors and recovery edits appear in the same event
stream.

Artifact identities can be inspected directly:

```text
:identity state 12
:identity conflict 1
:identity production 3
```

IDs use canonical semantic strings instead of Swift's randomized hashing.
Generation also traverses symbols and actions canonically, keeping numeric state
indices deterministic for an unchanged grammar and algorithm.

### `:diagram` and `:export`

Graphical artifacts use reusable renderers in `GrammarREPLCore`:

```text
:diagram grammar
:diagram rule expression
:diagram automaton
:diagram state 12
:diagram conflict 1
:diagram tree

:export automaton automaton.dot
:export state:12 state-12.dot
:export conflict:1 conflict-1.dot
:export rule:expression expression.txt
:export tree parse-tree.dot
```

Grammar and rule diagrams use the Grammar package's ASCII railroad renderer.
Automata, individual LR states, conflict explanations, and syntax trees use
Graphviz DOT. A conflict explanation highlights the shortest witness path and
conflict state, connects every candidate to its action origin and stable IDs,
shows the explicit resolution decision, and reports the outcome obtained by
replaying each forced branch. Export writes the renderer's content without
invoking an external viewer, so the library remains usable in tests and
headless tools.

### History and completion

The macOS CLI uses the system libedit library. Up/down navigation recalls
history, which is persisted in `~/.grammar-repl-history`; adjacent duplicate and
blank commands are omitted. `:history` displays the current session history.

Tab completion is driven by `GrammarREPLCore.CommandCompletion`: it completes
command names, parser names, loaded nonterminals, generated LR state/conflict
numbers, and diagram kinds. The terminal adapter only presents candidates and
does not duplicate semantic command knowledge.

### `:help` and `:quit`

`:help` (or `:?`) displays the concise command summary. `:quit`, `:exit`, and
`:q` end the session.

## Workbench and editor integration

`GrammarREPLCore` now provides a UI-independent boundary for a graphical
workbench. `GrammarWorkbenchService` owns open documents and accepts complete or
UTF-16 ranged edits. Every successful analysis produces an immutable
`WorkbenchDocumentSnapshot` tagged with the source revision; invalid source
produces structured diagnostics instead of a stale artifact.

```swift
let service = GrammarWorkbenchService()
let snapshot = service.open(
    uri: documentURL,
    source: grammarText,
    revision: 1,
    configuration: .init(notation: .bnf, start: "expression", algorithm: .lalr)
)

let json = try snapshot.artifact?.json()
```

### Versioned artifact snapshots

`WorkbenchArtifactEnvelope` schema version 1 serializes normalized productions,
FIRST/FOLLOW and LL conflicts, LR states and items, transitions, ACTION/GOTO
entries, decisions, candidate origins, stable identities, conflicts, and
witnesses. JSON keys and collections are emitted deterministically. Decoding
rejects unsupported schema versions, allowing a workbench to fail explicitly
instead of silently misreading a changed model.

The envelope is a view/interchange model, not a replacement for `Grammar` or
`LRAutomaton`. Clients should use the source revision and stable identities to
discard stale responses and preserve cross-view selections.

### Conflict minimization

`LRConflictMinimizer.minimize(_:in:)` delta-debugs a shortest witness while
requiring replay to continue reaching the same conflict cell. Its result also
contains the productions directly responsible for competing candidates.
`minimizeGrammar(reproducing:grammar:algorithm:)` goes further: it removes one
production at a time, regenerates the automaton, and retains the removal only
while the same conflict kind, lookahead, and action/production signature remain.
The result is therefore a standalone reproducing `Grammar`, not merely a list
of apparently relevant rules.

### Benchmark and stress instrumentation

`LRBenchmarkHarness.measure` runs selected algorithms and records generation
duration, state count, transition count, and conflict count for each iteration.
It intentionally does not embed timing thresholds: CI callers can compare JSON
reports to platform-specific baselines without making unit tests depend on
machine speed. The tests exercise structural assertions; LR-Parsing's grammar
fuzzer continues to supply randomized generation and identity invariants.

### Incremental parsing prototype

`IncrementalLRSession` retains the previous source and traced result. It reports
the common UTF-16 prefix and suffix, the invalidated range, and the number of
trace checkpoints preceding the edit. An unchanged source reuses its previous
result. Edited input is currently parsed normally and fully validated; the
metrics expose where a future resumable LR engine can restart without claiming
subtree or stack reuse that has not occurred yet.

### Language-server façade

`GrammarLanguageServer` maps editor operations onto the same document service:

- `didOpen`, incremental/full `didChange`, and `didClose`;
- grammar diagnostics;
- nonterminal completion and definition lookup;
- the custom versioned artifact response used by rich visual clients.

Positions use the Language Server Protocol's zero-based UTF-16 line/character
convention. The façade is transport-neutral: JSON-RPC headers, process lifetime,
and diagnostic publication are left to a small host executable or editor
extension. This keeps protocol framing separate from grammar semantics and
makes the service directly testable.

## Architecture and inner workings

The executable is a thin entry point. Command decoding, session state, shared
analysis, execution, and rendering live in the testable `GrammarREPLCore`
library target:

```text
terminal input
    ↓
REPLCommand.decode
    ↓
GrammarREPL.execute
    ↓
Grammar analysis or parser package
    ↓
text renderer and retained REPLSession state
```

The separate `grammar-repl-conformance` executable is a non-terminal adapter
for the shared ecosystem corpus. Its decoding, normalized-token LR execution,
bounded recovery, and structured observations live in `GrammarReplLib`. Corpus
versions 1 and 2 are accepted, with version 2 adding normalized tree roots;
readline, command history, and formatted terminal output are not part of the
conformance result.

### Command decoding

`REPLCommand` is an enum containing one case for every supported operation.
`REPLCommand.decode(_:)` trims the input, separates the command name from its
argument, recognizes aliases, and constructs a typed command.

Using a typed command instead of switching directly on strings keeps syntax
handling separate from execution. Unit tests exercise command decoding without
starting an interactive terminal.

An ordinary line becomes `.parse(line)`. A colon-prefixed line is decoded as a
command. Unknown or incomplete commands become `.unknown`, allowing the REPL to
report the problem without terminating.

### Session state

`REPLSession` retains only the state needed between commands:

```swift
struct REPLSession {
    var loaded: LoadedGrammar?
    var parser: REPLParser = .earley
    var lastInput: String?
    var lastTrees: [ParseTree] = []
}
```

`LoadedGrammar` retains:

- the standardized absolute file URL;
- inferred notation;
- optional explicit start name;
- the parsed `Grammar` value.

Retaining the loading parameters makes `:reload` deterministic. Retaining the
input together with its trees lets `:tree` resolve leaf ranges back into
lexemes.

The session follows simple invalidation rules:

| Operation        | Grammar  | Last input | Last trees |
| ---------------- | --------:| ----------:| ----------:|
| load/reload      | replaced | cleared    | cleared    |
| parser selection | retained | retained   | cleared    |
| successful parse | retained | replaced   | replaced   |
| analysis command | retained | retained   | retained   |

### Grammar analysis

FIRST and FOLLOW sets come directly from `Grammar.firstAndFollow()`. PREDICT
sets are calculated locally because they combine the FIRST set of a production
sequence with FOLLOW information for nullable alternatives.

LL(1) conflict detection groups productions by goal nonterminal, compares every
pair of alternatives, and records nonempty PREDICT-set intersections. The
algorithm is quadratic in the number of alternatives for one nonterminal, which
is appropriate for ordinary grammar sizes and makes every conflicting pair
explicit.

LL conflict results are public values in the shared analysis API:

```swift
public struct LLConflict {
    let nonterminal: NonTerminal
    let first: Production
    let second: Production
    let lookaheads: Set<Symbol>
}
```

`GrammarAnalysis` publishes FIRST, FOLLOW, per-production PREDICT sets, and LL
conflicts so command-line, test, and future graphical clients use one result.

### Parser execution

The generalized parsers return `[ParseTree]` through `allSyntaxTrees(for:)`.
Deterministic LR parsers return a shared `ParserOutcome` containing status,
tree, diagnostics, and recovery edits, which the REPL adapts into its retained
tree list.

If deterministic parsers later return a single tree while generalized parsers
return forests or multiple trees, the natural common boundary is a richer parse
outcome rather than forced type erasure:

```swift
struct ParserOutcome {
    let status: ParseStatus
    let trees: [ParseTree]
    let diagnostics: [ParserDiagnostic]
    let recoveryEdits: [RecoveryEdit]
}
```

### Tree rendering

`ParseTree` leaves contain `Range<String.Index>` values. `renderTree(_:in:)`
walks the tree recursively and slices the retained input for every leaf. It
renders nonterminals as branches and lexemes as quoted leaves.

Rendering is intentionally REPL-owned presentation logic. It does not modify
the shared tree representation and therefore does not affect compiler adapters
or parser packages.

### Error containment

Each command is executed inside one `do`/`catch` boundary. File errors, grammar
construction errors, unknown nonterminals, and parser errors are printed as
command failures, after which the next prompt is displayed. `:quit` is the only
command that deliberately ends normal execution.

Generalized parsers still display their existing error descriptions. LR modes
consume the shared structured diagnostics and explicit recovery edits published
by LR-Parsing.

## Relationship to the three-service design

The intended mature architecture separates three reusable services:

1. **Grammar analysis** — nullable, FIRST, FOLLOW, PREDICT, hygiene, recursion,
   factoring, and LL conflicts.
2. **Parser generation** — LL/LR tables, LR automata, states, transitions,
   action origins, and grammar conflicts for a selected deterministic algorithm.
3. **Parser runtime** — recognition, syntax trees or forests, diagnostics,
   tracing, and recovery for sample input.

The REPL consumes all three concepts: `GrammarAnalysis`, LR-Parsing's public
`LRAutomaton`, and generalized or deterministic parser runtimes.

The REPL should remain a client of these services. Conflict detection, recovery,
and graph construction should not be implemented only inside the executable,
because command-line tools, tests, IDE integrations, and graphical frontends
will need the same information.

## LR exploration model

LR-Parsing exposes the generation artifact used by these commands:

```text
:parser lalr
:check
:conflicts
:explain 1
:replay 1
:state 12
```

The required public model should contain at least:

- stable state identifiers for one generated automaton;
- LR items and lookahead sets in every state;
- terminal and nonterminal transitions;
- ACTION and GOTO table entries;
- every candidate action before conflict resolution;
- the item or production that originated each action;
- an explicit selected action and resolution policy for every ACTION cell;
- replay steps that take a shortest witness to its conflict decision point;
- unresolved and future precedence-resolved conflicts.

With that model, `:state 12` is a renderer; the REPL does not duplicate table
generation or parse diagnostic strings.

## Error recovery

Recovery lives in the LR runtime. The public API accepts these policies:

```text
:recover off
:recover panic
:recover repair
```

The parser outcome should then expose explicit edits:

```swift
enum RecoveryEdit {
    case insert(terminal: Terminal, at: SourcePosition)
    case delete(token: TokenDescription)
    case replace(token: TokenDescription, with: Terminal)
    case skip(range: SourceSpan, until: Terminal)
}
```

The REPL could render them inline:

```text
Original:
  if (x > 3 { print x; }

Recovered:
  if (x > 3 ⟦+)⟧ { print x; }
```

The notation means the closing parenthesis was synthesized; the input itself
was not silently changed. Recovery must always retain an error diagnostic and
distinguish clean acceptance from acceptance with recovery.

## Graphical artifact integration

A graphical grammar module consumes the same structured artifacts that the text
commands consume. The currently connected commands include:

```text
:diagram grammar
:diagram rule expression
:diagram automaton
:diagram state 12
:diagram conflict 1
:diagram tree
:export state:12 state-12.dot
:export conflict:1 conflict-1.dot
```

The boundary is the `GrammarArtifactRenderer` protocol:

```swift
protocol GrammarArtifactRenderer {
    associatedtype Artifact
    func render(
        _ artifact: Artifact,
        context: RenderingContext
    ) throws -> RenderedOutput
}
```

The grammar, LR automaton, conflict, parse forest, or syntax tree remains the
source of truth. The graphical module should not reconstruct semantic
information from the REPL's formatted text.

This separation also permits several outputs from one session artifact:

- concise terminal text;
- verbose diagnostic text;
- Graphviz or SVG;
- JSON for tooling;
- an in-app interactive visualization.

## Design principles

The prototype follows several principles intended to survive later expansion:

1. **The session owns interaction state, not parser semantics.**
2. **Library packages remain responsible for analysis and parsing.**
3. **Commands operate on structured values rather than each other's output.**
4. **A grammar edit invalidates results derived from the old grammar.**
5. **A parser change invalidates trees produced by the old parser.**
6. **Generalized ambiguity is preserved as multiple derivations.**
7. **Internal source ranges are rendered as source text for human inspection.**
8. **Missing advanced features are explicit rather than simulated by fragile
   text processing.**

## Testing and verification

Build only the REPL:

```sh
swift build --product grammar-repl
```

Run the repository's complete tests:

```sh
swift test
```

A useful manual smoke-test sequence is:

```text
:load Examples/arithmetic.bnf program
:check
:first expression
:follow expression
:predict expression
:parser earley
:parse print 1 + 2 * 3;
:tree
:settings
:quit
```

Expected properties:

- the grammar loads with `program` as its start symbol;
- `:check` reports LL(1) conflicts caused by left recursion;
- FIRST, FOLLOW, and PREDICT output is deterministic in display order;
- Earley accepts the sample;
- one derivation is retained;
- tree leaves display source lexemes rather than index ranges;
- the process exits normally.

---

## License

MIT License — see [LICENSE](LICENSE) for details.
