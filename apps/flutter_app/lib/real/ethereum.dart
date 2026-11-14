import 'dart:convert';
import 'dart:typed_data';
import 'package:web3dart/web3dart.dart' as eth;
import 'api.dart';

final uintMax = (BigInt.one << 256) - BigInt.one;
final _addressPattern = RegExp(r'^0x[0-9a-fA-F]{40}$');
final _hashPattern = RegExp(r'^0x[0-9a-fA-F]{64}$');
final _uintPattern = RegExp(r'^[0-9]{1,78}$');

String address(dynamic value) {
  if (value is! String ||
      !_addressPattern.hasMatch(value) ||
      BigInt.parse(value.substring(2), radix: 16) == BigInt.zero) {
    throw const FormatException('Địa chỉ Ethereum không hợp lệ.');
  }
  return value.toLowerCase();
}

BigInt uint(dynamic value) {
  if (value is! String || !_uintPattern.hasMatch(value)) {
    throw const FormatException('uint256 phải là chuỗi số nguyên.');
  }
  final number = BigInt.parse(value);
  if (number > uintMax) throw const FormatException('uint256 vượt giới hạn.');
  return number;
}

String word(BigInt value) {
  if (value < BigInt.zero || value > uintMax)
    throw const FormatException('uint256 vượt giới hạn.');
  return value.toRadixString(16).padLeft(64, '0');
}

String addressWord(dynamic value) =>
    address(value).substring(2).padLeft(64, '0');
String hashWord(dynamic value) {
  if (value is! String || !_hashPattern.hasMatch(value))
    throw const FormatException('bytes32 không hợp lệ.');
  return value.substring(2).toLowerCase();
}

String selector(String signature) =>
    eth.bytesToHex(eth.keccakUtf8(signature)).substring(0, 8);
String staticCall(String signature, List<String> words) =>
    '0x${selector(signature)}${words.join()}';

String encodeCreatePlan(Json draft) =>
    staticCall('createPlan(bytes32,address,uint256,uint32,uint64,uint64)', [
      hashWord(draft['client_reference']),
      addressWord(draft['token_address']),
      word(uint(draft['price_per_period'])),
      word(BigInt.from(draft['total_periods'] as int)),
      word(BigInt.from(draft['period_duration_seconds'] as int)),
      word(BigInt.from(draft['grace_period_seconds'] as int)),
    ]);
String encodeId(String method, String id) =>
    staticCall('$method(uint256)', [word(uint(id))]);
String encodeApprove(String vault, String amount) => staticCall(
  'approve(address,uint256)',
  [addressWord(vault), word(uint(amount))],
);
String encodeAllowance(String owner, String vault) => staticCall(
  'allowance(address,address)',
  [addressWord(owner), addressWord(vault)],
);
String encodeBalance(String owner) =>
    staticCall('balanceOf(address)', [addressWord(owner)]);

const checkInFields = [
  {'name': 'subscriptionId', 'type': 'uint256'},
  {'name': 'merchant', 'type': 'address'},
  {'name': 'periodIndex', 'type': 'uint256'},
  {'name': 'nonce', 'type': 'uint256'},
  {'name': 'deadline', 'type': 'uint256'},
];

Json typedData(Json config, Json message) => {
  'types': {
    'EIP712Domain': [
      {'name': 'name', 'type': 'string'},
      {'name': 'version', 'type': 'string'},
      {'name': 'chainId', 'type': 'uint256'},
      {'name': 'verifyingContract', 'type': 'address'},
    ],
    'CheckIn': checkInFields,
  },
  'primaryType': 'CheckIn',
  'domain': {
    'name': 'PrepaidGuard',
    'version': '1',
    'chainId': config['chain_id'],
    'verifyingContract': config['vault_address'],
  },
  'message': message,
};

Uint8List checkInDigest(Json domain, Json message) {
  final domainType = eth.bytesToHex(
    eth.keccakUtf8(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)',
    ),
  );
  final domainWords =
      domainType +
      eth.bytesToHex(eth.keccakUtf8(domain['name'] as String)) +
      eth.bytesToHex(eth.keccakUtf8(domain['version'] as String)) +
      word(BigInt.from(domain['chainId'] as int)) +
      addressWord(domain['verifyingContract']);
  final messageWords =
      eth.bytesToHex(
        eth.keccakUtf8(
          'CheckIn(uint256 subscriptionId,address merchant,uint256 periodIndex,uint256 nonce,uint256 deadline)',
        ),
      ) +
      word(uint(message['subscriptionId'])) +
      addressWord(message['merchant']) +
      word(uint(message['periodIndex'])) +
      word(uint(message['nonce'])) +
      word(uint(message['deadline']));
  return eth.keccak256(
    Uint8List.fromList([
      0x19,
      0x01,
      ...eth.keccak256(eth.hexToBytes(domainWords)),
      ...eth.keccak256(eth.hexToBytes(messageWords)),
    ]),
  );
}

String recoverCheckIn(Json domain, Json message, String signature) {
  if (!RegExp(r'^0x[0-9a-fA-F]{130}$').hasMatch(signature))
    throw const FormatException('Chữ ký QR không hợp lệ.');
  final raw = eth.hexToBytes(signature);
  final r = BigInt.parse(eth.bytesToHex(raw.sublist(0, 32)), radix: 16);
  final s = BigInt.parse(eth.bytesToHex(raw.sublist(32, 64)), radix: 16);
  final halfOrder = BigInt.parse(
    '7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0',
    radix: 16,
  );
  if (r == BigInt.zero ||
      s == BigInt.zero ||
      s > halfOrder ||
      ![27, 28].contains(raw[64]))
    throw const FormatException('Chữ ký không canonical.');
  final publicKey = eth.ecRecover(
    checkInDigest(domain, message),
    eth.MsgSignature(r, s, raw[64]),
  );
  return address('0x${eth.bytesToHex(eth.publicKeyToAddress(publicKey))}');
}

Json parseQr(String input, Json config) {
  if (utf8.encode(input).length > 4096)
    throw const FormatException('QR vượt 4096 bytes.');
  final decoded = jsonDecode(input);
  if (decoded is! Map<String, dynamic>)
    throw const FormatException('QR phải là JSON object.');
  if (decoded.keys.toSet().difference({
        'version',
        'kind',
        'chainId',
        'verifyingContract',
        'message',
        'signature',
      }).isNotEmpty ||
      decoded['version'] != 1 ||
      decoded['kind'] != 'PREPAIDGUARD_CHECK_IN' ||
      decoded['chainId'] != config['chain_id'] ||
      address(decoded['verifyingContract']) !=
          address(config['vault_address'])) {
    throw const FormatException('QR sai loại, network hoặc Vault.');
  }
  final message = decoded['message'];
  if (message is! Map<String, dynamic> ||
      message.keys
          .toSet()
          .difference(checkInFields.map((f) => f['name']!).toSet())
          .isNotEmpty ||
      message.length != 5) {
    throw const FormatException('Thông điệp QR không đúng schema.');
  }
  for (final field in ['subscriptionId', 'periodIndex', 'nonce', 'deadline']) {
    uint(message[field]);
  }
  address(message['merchant']);
  if (decoded['signature'] is! String)
    throw const FormatException('QR thiếu chữ ký.');
  return decoded;
}

String encodeCheckIn(Json message, String signature) {
  if (!RegExp(r'^0x[0-9a-fA-F]{130}$').hasMatch(signature))
    throw const FormatException('Chữ ký sai độ dài.');
  final head = [
    word(uint(message['subscriptionId'])),
    addressWord(message['merchant']),
    word(uint(message['periodIndex'])),
    word(uint(message['nonce'])),
    word(uint(message['deadline'])),
    word(BigInt.from(6 * 32)),
  ].join();
  final bytes = signature.substring(2);
  return '0x${selector('checkInWithSignature((uint256,address,uint256,uint256,uint256),bytes)')}$head${word(BigInt.from(65))}${bytes.padRight(192, '0')}';
}
