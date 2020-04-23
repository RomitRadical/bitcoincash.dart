import 'dart:convert';
import 'dart:typed_data';
import 'package:bitbox/bitbox.dart' as bitbox;
import 'package:http/http.dart';

class BCH {
  String getMnemonic() {
    String mnemonic = bitbox.Mnemonic.generate();
    return mnemonic;
  }

  Uint8List getSeed({String mnemonic}) {
    if (mnemonic == null) {
      mnemonic = getMnemonic();
    }

    Uint8List seed = bitbox.Mnemonic.toSeed(mnemonic);
    return seed;
  }

  bitbox.HDNode getMasterNode(
      {String mnemonic, Uint8List seed, bool testnet = false}) {
    if (seed == null) {
      seed = getSeed(mnemonic: mnemonic);
    }
    bitbox.HDNode masterNode = bitbox.HDNode.fromSeed(seed, testnet);
    return masterNode;
  }

  bitbox.HDNode getAccountNode(
      {String mnemonic,
      bitbox.HDNode masternode,
      bool isSlp = false,
      String bchpath = "m/44'/145'/0'",
      String slppath = "m/44'/245'/0'"}) {
    if (masternode == null) {
      masternode = getMasterNode(mnemonic: mnemonic);
    }
    bitbox.HDNode accountNode =
        masternode.derivePath(isSlp ? slppath : bchpath);
    return accountNode;
  }

  bitbox.HDNode getChildNode(
      {String mnemonic,
      String xPriv,
      bitbox.HDNode accountnode,
      int child = 0}) {
    if (accountnode == null) {
      if (mnemonic != null) {
        accountnode = getAccountNode(mnemonic: mnemonic);
      } else if (xPriv != null) {
        accountnode = bitbox.HDNode.fromXPriv(xPriv);
      }
    }
    return accountnode.derive(child);
  }

  String getXPriv({String mnemonic, bitbox.HDNode childnode}) {
    if (childnode == null) {
      childnode = getChildNode(mnemonic: mnemonic);
    }
    String xpriv = childnode.toXPriv();
    return xpriv;
  }

  String getCashAddress(
      {String mnemonic, String xPriv, bitbox.HDNode childnode}) {
    if (childnode == null) {
      if (mnemonic != null) {
        childnode = getChildNode(mnemonic: mnemonic);
        return childnode.toCashAddress();
      } else if (xPriv != null) {
        childnode = getChildNode(xPriv: xPriv);
      }
    }
    return childnode.toCashAddress();
  }

  String getSlpAddress({String mnemonic, String xPriv, String cashAddress}) {
    if (cashAddress == null) {
      if (mnemonic != null) {
        cashAddress = getCashAddress(mnemonic: mnemonic);
      } else if (xPriv != null) {
        cashAddress = getCashAddress(xPriv: xPriv);
      }
    }
    String slpAddress = bitbox.Address.toSLPAddress(cashAddress);
    return slpAddress;
  }

  convertAddr(String addr) {
    String legacyAddr;
    String cashAddr;
    String slpAddr;

    try {
      legacyAddr = bitbox.Address.toLegacyAddress(addr);
      slpAddr = bitbox.Address.toSLPAddress(legacyAddr);
      cashAddr = bitbox.Address.toCashAddress(legacyAddr);
    } catch (_) {
      legacyAddr = addr;
      cashAddr = bitbox.Address.toCashAddress(addr);
      slpAddr = bitbox.Address.toSLPAddress(addr);
    }
    print(legacyAddr);
    print(cashAddr);
    print(slpAddr);
  }

  createAccount() {
    String mnemonic = getMnemonic();
    String xPriv = getXPriv(mnemonic: mnemonic);
    String cashAddress = getCashAddress(xPriv: xPriv);

    print(mnemonic);
    print(xPriv);
    print(cashAddress);
  }

  sendOpReturn(String message, String cashaddress,
      [bool testnet = false]) async {
    var builder = bitbox.Bitbox.transactionBuilder(testnet: testnet);
    String message = "test flutter op return";
    var data = bitbox.compile(
        [bitbox.Opcodes.OP_RETURN, Uint8List.fromList(message.codeUnits)]);
    builder.addOutput(data, 0);
  }

  decodeOpReturn() {
    var message = "7465737420666c7574746572206f702072657475726e";
  }

  Future<double> getTestnetBalance(String address) async {
    var addresses = {
      "addresses": [address]
    };
    Response response = await post(
        "https://tapi.fullstack.cash/v3/blockbook/balance",
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(addresses));
    var data = jsonDecode(response.body);
    int satoshis = 0;
    for (var i = 0; i < data.length; i++) {
      satoshis += int.parse(data[i]['balance']);
    }
    return bitbox.BitcoinCash.fromSatoshi(satoshis);
  }

  Future<List> getTestnetUtxos(String address) async {
    var addresses = {
      "addresses": [address]
    };
    Response response = await post(
        "https://tapi.fullstack.cash/v3/blockbook/utxos",
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(addresses));
    var data = jsonDecode(response.body);
    List utxos = [];
    for (var i = 0; i < data.length; i++) {
      for (var j = 0; j < data[i].length; j++) {
        utxos.add(data[i][j]);
      }
    }
    return utxos;
  }

  getUtxos(String address) async {
    // must be a cash addr
    var res;
    try {
      bitbox.Address.toLegacyAddress(address);
    } catch (_) {
      throw new Exception(
          "Not an a valid address format, must be cashAddr or Legacy address format.");
    }
    res = await bitbox.Address.utxo(address) as List<bitbox.Utxo>;
    return res;
  }

  mapToBCHUtxoArray(List utxos, String xpriv) {
    List utxo = [];
    utxos.forEach((txo) => utxo.add({
          'satoshis': txo.satoshis,
          'xpriv': xpriv,
          'txid': txo.txid,
          'vout': txo.vout
        }));
    return utxo;
  }

  sendBCH(String bchaddress, String bchxpriv, String bchsendaddr) async {
    List utxos = await BCH().getUtxos(bchaddress);
    var transactionBuilder = bitbox.TransactionBuilder();
    List<Map> signatures = [];
    int totalSatoshis = 0;
    utxos.forEach((txo) {
      transactionBuilder.addInput(txo.txid, txo.vout);
      totalSatoshis += txo.satoshis;
      var childNode = BCH().getChildNode(xPriv: bchxpriv);
      signatures.add({
        'keypair': childNode.keyPair,
        'satoshis': txo.satoshis,
        "vin": signatures.length,
      });
    });
    int fee = bitbox.BitcoinCash.getByteCount(signatures.length, 1);
    transactionBuilder.addOutput(bchsendaddr, totalSatoshis - fee);
    signatures.forEach((i) {
      transactionBuilder.sign(i['vin'], i['keypair'], i['satoshis']);
    });
    var hex = transactionBuilder.build().toHex();
    var txid = await bitbox.RawTransactions.sendRawTransaction(hex);
    print(txid);
  }
}
