# Attest testing language

Vocabulary for the 1.0 design. Result accessors now distinguish runtime
case identity from source-definition identity; the run and discovery
records remain plist-compatible while the migration continues.

## Language

**Backend**:
A provider of test discovery and execution for a particular testing framework.
_Avoid_: Language, consumer

**Definition**:
A test or suite declaration in source. One definition can produce several runtime cases.
_Avoid_: Result, runtime case

**Namespace**:
A named grouping of definitions, such as a suite, class or module.

**Runtime case**:
An individual test instance executed by a framework, including a particular parameter combination.
_Avoid_: Definition

**Execution target**:
A framework execution context in which runtime case identities are meaningful, such as a Cargo test executable.
_Avoid_: Selection

**Selection**:
The tests requested by the user, expressed as files, definitions, namespaces or runtime cases.
_Avoid_: Execution target

**Selector**:
A framework-specific expression used to ask a runner to execute a selection.
_Avoid_: Identity

**Run request**:
The user's intent to execute a selection using a backend and its configuration.
_Avoid_: Run state

**Run**:
One attempt to fulfill a run request, from preparation through completion or cancellation.
_Avoid_: Process

**Invocation**:
One runner execution within a run, associated with an execution target.
_Avoid_: Run

**Result**:
The recorded outcome of a runtime case in a run, including its failures and timing.
_Avoid_: Definition, status marker

**Discovery snapshot**:
The definitions known for a particular version of the source, together with whether discovery was complete.

**Run error**:
A failure of preparation, collection, execution infrastructure or result interpretation that prevents a trustworthy complete account of a run.
_Avoid_: Test failure

**Consumer**:
A presentation of test state, such as fringe markers, diagnostics or a results list.
_Avoid_: Backend
