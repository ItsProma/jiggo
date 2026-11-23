import 'auth_service.dart';

import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';

import 'local_file_store.dart';
import 'pdf_delivery.dart';

abstract class LocalFileSaver {
  Future<void> save(
    String filename,
    LocalFileKind kind,
    Uint8List bytes,
    String source,
  );
}

/// Capture the owner before encoding, so an account change cannot redirect data.
class AccountLocalFileSaver implements LocalFileSaver {
  final LocalFileStore? store;
  final String? Function()? currentOwner;
  final String? expectedOwner;
  AccountLocalFileSaver({this.store, this.currentOwner, this.expectedOwner});
  factory AccountLocalFileSaver.capture() {
    final user = FirebaseAuth.instance.currentUser;
    final owner = AuthService.isMember(user) ? user!.uid : null;
    if (owner == null) throw StateError('local-sign-in');
    return AccountLocalFileSaver(expectedOwner: owner);
  }
  String? _owner() => currentOwner != null
      ? currentOwner!()
      : AuthService.isMember(FirebaseAuth.instance.currentUser)
      ? FirebaseAuth.instance.currentUser!.uid
      : null;
  @override
  Future<void> save(
    String filename,
    LocalFileKind kind,
    Uint8List bytes,
    String source,
  ) async {
    final owner = expectedOwner ?? _owner();
    if (owner == null) throw StateError('local-sign-in');
    if (_owner() != owner) throw StateError('local-account-changed');
    await (store ?? deviceLocalFiles).save(
      owner,
      filename,
      kind,
      bytes,
      source,
    );
    if (_owner() != owner) throw StateError('local-account-changed');
  }
}

Future<PdfDelivery> saveLocalCopy(
  LocalFileSaver saver,
  String name,
  LocalFileKind kind,
  Uint8List bytes,
  String source,
) async {
  await saver.save(name, kind, bytes, source);
  return PdfDelivery.saved;
}

String localSaveFailure(Object error) =>
    error.toString().contains('local-library-full')
    ? 'Local Library is full (100 files or 64 MB). Download a backup, then delete some files and try again.'
    : 'Could not save to Library. Your draft is kept. Check free storage and your account, then try again.';
