import 'package:bitbox/bitbox.dart' as bitbox;
import 'package:bitcoincash/bch.dart';
import 'package:bitcoincash/slp.dart';
import 'package:flutter/material.dart';

void main() => runApp(MaterialApp(
      home: Main(),
    ));

class Main extends StatefulWidget {
  @override
  _MainState createState() => _MainState();
}

class _MainState extends State<Main> {
  String mnemonic =
      "sword beauty dutch accuse theory over shine labor hill empty kiss seven";
  String slpxpriv =
      "xprvA1ebytD6FrprapTnoTc5m8XYVjiigzqGi5KAkQwUunpC8QJ4WXtvCdC6Vt6DFqw44tQ4VaAKX9amAZ4kfTNJjXjc7GvNs6xjdJBGpp1heLT";
  String slpaddress = "simpleledger:qr28sv6ln5z2zelk9n767dshx6rkk0ztk5npdtnpc2";
  String changeaddress =
      "bitcoincash:qr28sv6ln5z2zelk9n767dshx6rkk0ztk5l6xsxpx5";

  String bchaddress = 'bitcoincash:qr3gey7cshwap4qks04rgx0np57ff5vrw5jqlz873w';
  String bchxpriv =
      'xprvA2Rcs5Ffm4fRgQEPsnfd28hEMif3JRq3KverSSMM1RaMHrBvQfoVzQCPnDQKisvUd3X5DUQ1LAS8TCnYJ7LHnpUisDyBqzzgMzTE9r8URCV';

  String tokenid =
      "a94c612ba8f636d80a69f797ef0a10caf5b431c98e82501c25b03022a73c2d7e";

  String sendslpaddress =
      "simpleledger:qqxhk78y2f0mtg43axcmyj7rqahwqwgyhcpzvhltur";

  @override
  void initState() {
    super.initState();
    sendSLP();
  }

  sendSLP() async {
    var slpUtxos = await SLP().getSlpUtxos(tokenid, slpaddress);
    var tokenInputUtxos = bitbox.SLP().mapToSLPUtxoArray(slpUtxos, slpxpriv);
    var bchUtxos = await BCH().getUtxos(bchaddress);
    var bchInputUtxos = BCH().mapToBCHUtxoArray(bchUtxos, bchxpriv);
    var hex = await SLP().simpleTokenSend(
        tokenId: tokenid,
        sendAmount: 1,
        inputUtxos: tokenInputUtxos,
        bchInputUtxos: bchInputUtxos,
        tokenReceiverAddress: sendslpaddress,
        slpChangeReceiverAddress: slpaddress,
        bchChangeReceiverAddress: bchaddress);
    var txid = await bitbox.RawTransactions.sendRawTransaction(hex);
    return print(txid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
          child: Container(
        padding: EdgeInsets.all(15),
        child: Text(
          slpaddress,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
      )),
    );
  }
}
