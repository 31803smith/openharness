import 'dart:async';
import 'dart:typed_data';

import 'package:harness_mobile/api/api_client.dart';
import 'package:harness_mobile/auth/auth_session.dart';
import 'package:harness_mobile/auth/cli_link.dart';
import 'package:harness_mobile/auth/cli_login.dart';
import 'package:harness_mobile/auth/peer_link_client.dart';
import 'package:harness_mobile/auth/sign_in_client.dart';
import 'package:harness_mobile/core/config.dart';
import 'package:harness_mobile/core/machine_cache.dart';
import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/viewer/direct_auth.dart';
import 'package:harness_mobile/viewer/direct_auth_api.dart';
import 'package:harness_mobile/viewer/direct_link.dart';
import 'package:harness_mobile/viewer/direct_login.dart';
import 'package:harness_mobile/viewer/email_code_api.dart';
import 'package:harness_mobile/viewer/email_code_login.dart';
import 'package:harness_mobile/viewer/viewer_key_store.dart';
import 'package:harness_mobile/viewer/viewer_services.dart';
import 'package:harness_mobile/ws/relay_codec.dart';
import 'package:harness_mobile/ws/terminal_transport_plugin.dart';
import 'package:harness_mobile/ws/ws_conn.dart';

import 'agent_pager_fixture.dart';
import 'viewer/fake_http.dart';
import 'voice_fakes.dart' show MemoryKeyValueStore;

/// The phone app with everything outside the process faked: the account's REST
/// API ([FakeApi]), each machine's socket ([ScriptedConn]), the sign-in
/// ([FakeSignIn], [FakeEmailLogin]) and the links to machines ([FakeLinks]).
///
/// ⚠️ **Nothing here may reach a real account, a real daemon or a real
/// `~/.harness`.** The session is kept in memory, every HTTP client answers from
/// a map ([FakeHttp]), and no [WsConn] ever dials — a [ScriptedConn] is built
/// with an address that does not resolve and never has `connect` called.

/// A machine's socket that answers each request type from [answers], and
/// remembers everything it was asked and sent.
class ScriptedConn extends PagerConn {
  ScriptedConn({this.ready = true});

  /// Whether the handshake is done — what `isReady` and `waitUntilReady` say.
  bool ready;

  /// Whether the socket has given up for good ([WsConn.isClosed]).
  bool closed = false;

  /// Request type → its reply. A type with no entry answers `{}`. Throwing
  /// stands for a refusal ([WsRequestFailure]), a timeout
  /// ([WsRequestTimeout]) or a dropped socket.
  final Map<
    String,
    FutureOr<Map<String, dynamic>> Function(Map<String, dynamic> payload)
  >
  answers = {};

  final List<(String, Map<String, dynamic>)> requests = [];
  final List<Uint8List> binaries = [];
  int redials = 0;

  /// The request types asked, in order.
  List<String> get asked => [for (final (type, _) in requests) type];

  /// The payloads of every request of [type].
  List<Map<String, dynamic>> payloadsOf(String type) => [
    for (final (asked, payload) in requests)
      if (asked == type) payload,
  ];

  @override
  bool get isReady => ready;

  @override
  bool get isClosed => closed;

  @override
  Future<void> waitUntilReady({required Duration timeout}) async {
    if (!ready) throw const WsRequestTimeout('machine_select');
  }

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    requests.add((type, payload));
    final answer = answers[type];
    if (answer == null) return {};
    return await answer(payload);
  }

  @override
  Future<bool> sendTerminalBinary(Uint8List bytes) async {
    binaries.add(bytes);
    return true;
  }

  @override
  Future<void> forceReconnect() async => redials++;
}

/// A refusal from the machine, as `request` throws it.
WsRequestFailure refusal(String code, {String? detail}) =>
    WsRequestFailure(responseType: 'result', code: code, detail: detail);

/// The account's REST API: `/api/machines`, `/api/auth/me` and the desk.
class FakeApi extends ApiClient {
  FakeApi()
    : super(
        config: AppConfig.dev,
        session: AuthSession(storage: MemoryKeyValueStore()),
      );

  /// What `/api/machines` answers; replace to change the account, or throw
  /// from it for an account that cannot be read.
  Future<List<Machine>> Function() onMachines = () async => const [];
  int machineFetches = 0;

  Map<String, dynamic>? profile = const {
    'user': {'id': 'u1', 'email': 'pat@example.com', 'name': 'Pat'},
  };
  int profileReads = 0;

  final List<String> renamed = [];
  final List<String> deleted = [];
  Object? renameFailure;
  Object? deleteFailure;

  @override
  Future<List<Machine>> machines() {
    machineFetches++;
    return onMachines();
  }

  @override
  Future<Map<String, dynamic>?> me() async {
    profileReads++;
    return profile;
  }

  @override
  Future<Map<String, dynamic>?> desk() async => null;

  @override
  Future<Map<String, dynamic>?> deskOps(List<Map<String, dynamic>> ops) async =>
      null;

  @override
  Future<String?> renameMachine({
    required String machineId,
    required String name,
  }) async {
    if (renameFailure case final failure?) throw failure;
    renamed.add('$machineId=$name');
    return name;
  }

  @override
  Future<void> deleteMachine({required String machineId}) async {
    if (deleteFailure case final failure?) throw failure;
    deleted.add(machineId);
  }
}

/// Whether the phone is signed in, as the viewer's session store would say.
class FakeSignIn implements SignInClient {
  FakeSignIn({this.signedIn = true});

  bool signedIn;

  /// Thrown by [checkStatus] when set: a session store that could not be read.
  Object? statusFailure;

  /// Held open until the test completes it.
  Completer<void>? statusGate;
  int cancels = 0;
  int logouts = 0;

  @override
  Future<CliAuthStatus> checkStatus() async {
    await statusGate?.future;
    if (statusFailure case final failure?) throw failure;
    return CliAuthStatus(loggedIn: signedIn);
  }

  @override
  Future<void> login({
    required void Function(String url) onAuthorizeUrl,
  }) async {}

  @override
  void cancel() => cancels++;

  @override
  Future<void> logout() async => logouts++;
}

/// The emailed-code and scanned-QR sign-in, with no service behind it.
class FakeEmailLogin implements EmailCodeLogin {
  final List<String> codesSent = [];
  final List<(String, String)> signIns = [];
  final List<(String, String)> scans = [];

  /// Thrown by the next sign-in when set: a wrong or expired code.
  Object? failure;

  /// Held open until the test completes it.
  Completer<void>? gate;

  @override
  DirectAuth get auth => throw UnimplementedError();

  @override
  Future<void> sendCode(String email) async => codesSent.add(email);

  @override
  Future<void> signIn({required String email, required String code}) async {
    signIns.add((email, code));
    await gate?.future;
    if (failure case final error?) throw error;
  }

  @override
  Future<void> signInWithScan(String code, {required String label}) async {
    scans.add((code, label));
    await gate?.future;
    if (failure case final error?) throw error;
  }
}

/// A viewer's services with every wire faked — see the note at the top.
class FakeViewer implements ViewerServices {
  FakeViewer(AuthSession session)
    : keys = ViewerKeyStore(storage: MemoryKeyValueStore()),
      auth = DirectAuth(
        session: session,
        api: DirectAuthApi(config: AppConfig.dev, dio: FakeHttp({}).dio()),
        emailCodes: EmailCodeApi(
          config: AppConfig.dev,
          dio: FakeHttp({}).dio(),
        ),
      );

  @override
  final ViewerKeyStore keys;

  @override
  final DirectAuth auth;

  @override
  final FakeEmailLogin emailLogin = FakeEmailLogin();

  @override
  DirectLogin get login => throw UnimplementedError('pass a FakeSignIn');

  @override
  DirectLink get links => throw UnimplementedError('pass FakeLinks');

  @override
  RelayCodecFactory get relayCodecs =>
      (_) => throw UnimplementedError('nothing dials');

  @override
  TerminalTransportPluginFactory? get transportPlugins => null;
}

/// Links to machines, answered by the test.
class FakeLinks implements PeerLinkClient {
  CliLinkConnectResult connectResult = const CliLinkConnectResult();
  CliLinkConnectResult codeResult = const CliLinkConnectResult();
  CliLinkListResult listResult = const CliLinkListResult();
  String? unlinkError;

  final List<(String, String)> passwords = [];
  final List<(String, String, String)> codes = [];
  final List<String> unlinked = [];
  int lists = 0;

  @override
  Future<CliLinkConnectResult> connect(
    String machineId,
    String password, {
    void Function(String stage)? onProgress,
    String? displayName,
  }) async {
    passwords.add((machineId, password));
    onProgress?.call('connecting');
    return connectResult;
  }

  @override
  Future<CliLinkConnectResult> connectWithCode(
    String machineId,
    String code, {
    required String label,
    String? displayName,
  }) async {
    codes.add((machineId, code, label));
    return codeResult;
  }

  @override
  Future<CliLinkListResult> list() async {
    lists++;
    return listResult;
  }

  @override
  Future<String?> unlink(String machineId) async {
    unlinked.add(machineId);
    return unlinkError;
  }
}

/// A remote machine as `/api/machines` lists it.
Machine remoteMachine(String id, {String? status = 'online', String? name}) =>
    Machine(
      machineId: id,
      authMode: MachineAuthMode.remote,
      name: name ?? 'Machine $id',
      status: status,
    );

/// An agent as a daemon sends it.
Map<String, dynamic> agentJson(
  String id, {
  String? name,
  String engine = 'claude',
  String? sessionId,
  bool terminal = true,
  String status = 'active',
  String? updatedAt,
  Map<String, dynamic>? extra,
}) => {
  'id': id,
  'name': name ?? id,
  'engine': engine,
  'sessionId': ?sessionId,
  'status': status,
  'updatedAt': ?updatedAt,
  'project': <String, dynamic>{'name': 'work', 'cwd': '/work'},
  'terminal': <String, dynamic>{'available': terminal},
  ...?extra,
};

/// What a daemon on a current CLI answers to `terminal_capabilities`.
Map<String, dynamic> capabilities({bool noTakeover = true}) => {
  'protocolVersion': 3,
  'backend': 'tmux',
  'available': true,
  'features': {
    'pasteRaw': true,
    'imagePaste': true,
    'pasteFile': true,
    'mediaPreview': true,
    'projectFolder': true,
    'noTakeover': noTakeover,
  },
};

/// Everything a [viewerApp] test reaches for.
class ViewerRig {
  ViewerRig({
    required this.app,
    required this.api,
    required this.signIn,
    required this.viewer,
    required this.links,
    required this.conns,
  });

  final AppNotifier app;
  final FakeApi api;
  final FakeSignIn signIn;
  final FakeViewer viewer;
  final FakeLinks links;

  /// One socket per machine id, made the first time the app asks for it.
  final Map<String, ScriptedConn> conns;

  ScriptedConn conn(String machineId) =>
      conns.putIfAbsent(machineId, ScriptedConn.new);
}

/// A phone app — a VIEWER, with no CLI beside it — signed out, on an account
/// whose machines [FakeApi.onMachines] lists.
ViewerRig viewerApp({
  bool signedIn = true,
  MachineCache? machineCache,
  Duration turnActivityTimeout = const Duration(seconds: 12),
}) {
  final session = AuthSession(storage: MemoryKeyValueStore());
  final viewer = FakeViewer(session);
  final signIn = FakeSignIn(signedIn: signedIn);
  final links = FakeLinks();
  final conns = <String, ScriptedConn>{};
  final app = AppNotifier(
    config: AppConfig.dev,
    authSession: session,
    configStore: null,
    cliLogin: signIn,
    cliLink: CliLink(),
    peerLinks: links,
    viewer: viewer,
    machineCache: machineCache,
    turnActivityTimeout: turnActivityTimeout,
    connectionForTest: (machineId) =>
        conns.putIfAbsent(machineId, ScriptedConn.new),
  );
  final api = FakeApi();
  app.api = api;
  return ViewerRig(
    app: app,
    api: api,
    signIn: signIn,
    viewer: viewer,
    links: links,
    conns: conns,
  );
}

/// Lets every pending microtask and zero-length timer run.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
