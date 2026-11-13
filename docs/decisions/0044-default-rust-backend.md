# 0044: Default app builds to the Rust backend

Status: proposed; requires the owner's explicit production-switch review.

The backend seam in 0040 keeps app operations and saved/wire JSON compatible
while choosing one implementation. Ordinary builds currently use Dart. This
separate change selects the pinned Rust core by default; both implementations
and the comparison tests remain. An explicit test-build
`--dart-define=FIREPLACE_RUST_CRYPTO=false` can still select Dart.

The selection affects local cryptographic operations only. It adds no network
request, server field, Firebase cost, dependency or stored-format migration.
Existing session snapshots continue through the same public app API. Android
and iOS must both contain the normal core library, with no test RNG exports.

Do not merge until the owner has explicitly reviewed this switch and the
Android and iOS packaging PRs have merged with their required checks passing.
The PR remains a draft until that review. Release signing, version selection
and upload retain their separate owner gates.

Run the full app checks with this default, including the dual-backend chat
simulation, and compare fresh renders. After a reviewed release has actually
run on Rust, removal of the Dart reference is still a separate owner decision;
this change does not authorize that removal.
