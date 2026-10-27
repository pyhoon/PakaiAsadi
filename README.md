# Pakai Asadi

Pakai Asadi is an embeddable SQLite administration component for B4J. The checkout is at milestone M0/M1 scaffolding: the ecosystem report and verified integration contract are in [RECONNAISSANCE.md](RECONNAISSANCE.md).

## Status

This repository was empty at task start. The current deliverable establishes the source-derived architecture before implementation. No library artifact, runnable demo, or tested administration routes are present yet. See the report for verified dependencies, security requirements and unresolved compatibility risks.

The reconnaissance report also covers Pakai Lanyard (session filter; host admin-role authorization still required), Pakai Vest (experimental MiniORM CRUD templates, not suited to arbitrary schema inspection), and Pakai Watch (optional rate-limit filter; inspected source logs bearer-token-derived client identifiers for blocked requests).

## Intended host integration

Use the host's existing EndsMeet 4.03 `App` instance. Register Asadi GET routes before the host calls `App.Start`. The public API is still being implemented; do not copy an illustrative API into production code yet. A host-provided authorization gate is mandatory, and the host must supply the SQLite JDBC driver on the runtime classpath.

## License

License selection is pending repository-owner confirmation. No license is asserted by this scaffold.
