// Builds the approved registry pin with the installed Android NDK. No cargo-ndk
// or other build dependency is needed. Gradle invokes this before packaging.
import 'dart:io';

const _targets = [
  (
    abi: 'arm64-v8a',
    rust: 'aarch64-linux-android',
    clang: 'aarch64-linux-android26',
  ),
  (
    abi: 'armeabi-v7a',
    rust: 'armv7-linux-androideabi',
    clang: 'armv7a-linux-androideabi26',
  ),
  (
    abi: 'x86_64',
    rust: 'x86_64-linux-android',
    clang: 'x86_64-linux-android26',
  ),
];

Future<void> run(
  String program,
  List<String> arguments, {
  required String cwd,
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    program,
    arguments,
    workingDirectory: cwd,
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  final result = await process.exitCode;
  if (result != 0) {
    throw ProcessException(program, arguments, 'Native build failed.', result);
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart scripts/build_crypto_android.dart <ndk> <jni-output>',
    );
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final rust = Directory('${root.path}/packages/fireplace_native/rust');
  final ndk = Directory(args[0]).absolute;
  final output = Directory(args[1]).absolute;
  final host = Platform.isWindows
      ? 'windows-x86_64'
      : Platform.isMacOS
      ? 'darwin-x86_64'
      : 'linux-x86_64';
  final clang = File(
    '${ndk.path}/toolchains/llvm/prebuilt/$host/bin/clang${Platform.isWindows ? '.exe' : ''}',
  );
  if (!clang.existsSync()) {
    throw StateError('The Android NDK compiler is missing.');
  }
  final targetDirectory = Directory(
    '${root.path}/build/fireplace_crypto/android',
  ).absolute;

  for (final target in _targets) {
    // Target installation uses only the Rust toolchain already approved in
    // decision 0035. A normal rebuild makes no changes when it is installed.
    await run('rustup', [
      '+1.98.1',
      'target',
      'add',
      target.rust,
    ], cwd: rust.path);
    final prefix =
        'CARGO_TARGET_${target.rust.replaceAll('-', '_').toUpperCase()}';
    await run(
      'cargo',
      [
        '+1.98.1',
        'build',
        '--package',
        'fireplace-crypto',
        '--lib',
        '--release',
        '--locked',
        '--target',
        target.rust,
        '--target-dir',
        targetDirectory.path,
      ],
      cwd: rust.path,
      environment: {
        '${prefix}_LINKER': clang.path,
        '${prefix}_RUSTFLAGS':
            '-C link-arg=--target=${target.clang} -C link-arg=-Wl,-z,max-page-size=16384',
      },
    );
    final library = File(
      '${targetDirectory.path}/${target.rust}/release/libfireplace_crypto.so',
    );
    if (!library.existsSync()) {
      throw StateError('The Android crypto library is missing.');
    }
    final folder = Directory('${output.path}/${target.abi}');
    await folder.create(recursive: true);
    await library.copy('${folder.path}/libfireplace_crypto.so');
  }
}
