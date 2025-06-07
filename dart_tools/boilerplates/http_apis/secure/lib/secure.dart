library toolchain.dart.boilerplate.http_apis.secure;

import 'package:encrypt/encrypt.dart';
import 'dart:convert';

export 'package:encrypt/encrypt.dart' show Key;

typedef JSON = Map<String, Object?>;

class Configs {
  static int keyBytesLength = 32;
  static int ivBytesLength = 16;
}

Key generateKey() => Key.fromSecureRandom(Configs.keyBytesLength);

JSON decryptPayload(Key key, String wrappedPayload) {
  final parsed = jsonDecode(wrappedPayload);

  final decryptedJsonString = Encrypter(
    AES(key, mode: AESMode.cbc),
  ).decrypt(
    Encrypted.fromBase64(parsed['cipher']),
    iv: IV.fromBase64(parsed['iv']),
  );
  return jsonDecode(decryptedJsonString);
}

String encryptPayload(Key key, JSON payload) {
  final iv = IV.fromLength(Configs.ivBytesLength);
  final encrypter = Encrypter(AES(key, mode: AESMode.cbc));

  final jsonString = jsonEncode(json);
  final encrypted = encrypter.encrypt(jsonString, iv: iv);

  return jsonEncode({
    'iv': iv.base64,
    'cipher': encrypted.base64,
  });
}
