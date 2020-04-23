import 'dart:convert';
import 'package:bitbox/bitbox.dart' as bitbox;
import 'package:http/http.dart';
import 'package:slp_mdm/slp_mdm.dart';
import 'package:slp_parser/slp_parser.dart';
import 'package:hex/hex.dart';

class SLP {
  getSlpUtxos(String tokenid, String slpaddress) async {
    // get token & non token utxos from slpjs
  }

  slpParser() {
    var scriptPubKey =
        '6a04534c50000101044d494e5420a94c612ba8f636d80a69f797ef0a10caf5b431c98e82501c25b03022a73c2d7e0102080000000000000001';
    var decodedHex = HEX.decode(scriptPubKey);
    var slpMsg = parseSLP(decodedHex);
    print('Parsed results: ${slpMsg.toMap()}');
  }

  slpMDM() {
    var tokenId = HEX.decode(
        'ff1b54b2141f81e07e0027d369db6484dea8d94429a635c35d17a7462a659239');
    var sendMsg = Send(tokenId, [BigInt.from(1), BigInt.from(10)]);
    print(HEX.encode(sendMsg));

    var mintMsg = Mint(tokenId, BigInt.from(1), 0x02);
    print(HEX.encode(mintMsg));
  }

  simpleTokenSend(
      {String tokenId,
      double sendAmount,
      List inputUtxos,
      List bchInputUtxos,
      String tokenReceiverAddress,
      String slpChangeReceiverAddress,
      String bchChangeReceiverAddress,
      List requiredNonTokenOutputs,
      int extraFee,
      int type = 0x01}) async {
    BigInt amount;
    if (tokenId is! String) {
      return Exception("Token id should be a String");
    }
    if (tokenReceiverAddress is! String) {
      throw new Exception("Token address should be a String");
    }
    try {
      if (sendAmount > 0) {
        amount = BigInt.from(sendAmount);
      }
    } catch (e) {
      return Exception("Invalid amount");
    }

    // 1 Set the token send amounts, we'll send 100 tokens to a
    //    new receiver and send token change back to the sender
    BigInt totalTokenInputAmount = BigInt.from(0);
    inputUtxos.forEach((txo) =>
        totalTokenInputAmount += _preSendSlpJudgementCheck(txo, tokenId));

    // 2 Compute the token Change amount.
    BigInt tokenChangeAmount = totalTokenInputAmount - amount;
    bool sendChange = tokenChangeAmount > new BigInt.from(0);

    String txHex;
    if (tokenChangeAmount < new BigInt.from(0)) {
      return throw Exception('Token inputs less than the token outputs');
    }
    // 3 Create the Send OP_RETURN message
    var sendOpReturn = Send(
        HEX.decode(tokenId),
        tokenChangeAmount > BigInt.from(0)
            ? [amount, tokenChangeAmount]
            : [amount]);
    // 4 Create the raw Send transaction hex
    txHex = await _buildRawSendTx(
        slpSendOpReturn: sendOpReturn,
        inputTokenUtxos: inputUtxos,
        bchInputUtxos: bchInputUtxos,
        tokenReceiverAddresses: sendChange
            ? [tokenReceiverAddress, slpChangeReceiverAddress]
            : [tokenReceiverAddress],
        bchChangeReceiverAddress: bchChangeReceiverAddress,
        requiredNonTokenOutputs: requiredNonTokenOutputs,
        extraFee: extraFee);

    // Return raw hex for this transaction
    return txHex;
  }

  BigInt _preSendSlpJudgementCheck(Map txo, tokenID) {
    if (txo['slpUtxoJudgement'] == "undefined" ||
        txo['slpUtxoJudgement'] == null ||
        txo['slpUtxoJudgement'] == "UNKNOWN") {
      throw Exception(
          "There is at least one input UTXO that does not have a proper SLP judgement");
    }
    if (txo['slpUtxoJudgement'] == "UNSUPPORTED_TYPE") {
      throw Exception(
          "There is at least one input UTXO that is an Unsupported SLP type.");
    }
    if (txo['slpUtxoJudgement'] == "SLP_BATON") {
      throw Exception(
          "There is at least one input UTXO that is a baton. You can only spend batons in a MINT transaction.");
    }
    if (txo.containsKey('slpTransactionDetails')) {
      if (txo['slpUtxoJudgement'] == "SLP_TOKEN") {
        if (!txo.containsKey('slpUtxoJudgementAmount')) {
          throw Exception(
              "There is at least one input token that does not have the 'slpUtxoJudgementAmount' property set.");
        }
        if (txo['slpTransactionDetails']['tokenIdHex'] != tokenID) {
          throw Exception(
              "There is at least one input UTXO that is a different SLP token than the one specified.");
        }
        if (txo['slpTransactionDetails']['tokenIdHex'] == tokenID) {
          return BigInt.from(double.parse(txo['slpUtxoJudgementAmount']));
        }
      }
    }
    return BigInt.from(0);
  }

  _buildRawSendTx(
      {List<int> slpSendOpReturn,
      List inputTokenUtxos,
      List bchInputUtxos,
      List tokenReceiverAddresses,
      String bchChangeReceiverAddress,
      List requiredNonTokenOutputs,
      int extraFee,
      type = 0x01}) async {
    // Check proper address formats are given
    tokenReceiverAddresses.forEach((addr) {
      if (!addr.startsWith('simpleledger:')) {
        throw new Exception("Token receiver address not in SlpAddr format.");
      }
    });

    if (bchChangeReceiverAddress != null) {
      if (!bchChangeReceiverAddress.startsWith('bitcoincash:')) {
        throw new Exception(
            "BCH/SLP token change receiver address is not in SlpAddr format.");
      }
    }

    // Parse the SLP SEND OP_RETURN message
    var sendMsg = parseSLP(slpSendOpReturn).toMap();
    Map sendMsgData = sendMsg['data'];

    // Make sure we're not spending inputs from any other token or baton
    var tokenInputQty = new BigInt.from(0);
    inputTokenUtxos.forEach((txo) {
      if (txo['slpUtxoJudgement'] == "NOT_SLP") {
        return;
      }
      if (txo['slpUtxoJudgement'] == "SLP_TOKEN") {
        if (txo['slpTransactionDetails']['tokenIdHex'] !=
            sendMsgData['tokenId']) {
          throw Exception("Input UTXOs included a token for another tokenId.");
        }
        tokenInputQty +=
            BigInt.from(double.parse(txo['slpUtxoJudgementAmount']));
        return;
      }
      if (txo['slpUtxoJudgement'] == "SLP_BATON") {
        throw Exception("Cannot spend a minting baton.");
      }
      if (txo['slpUtxoJudgement'] == ['INVALID_TOKEN_DAG'] ||
          txo['slpUtxoJudgement'] == "INVALID_BATON_DAG") {
        throw Exception("Cannot currently spend UTXOs with invalid DAGs.");
      }
      throw Exception("Cannot spend utxo with no SLP judgement.");
    });

    // Make sure the number of output receivers
    // matches the outputs in the OP_RETURN message.
    if (tokenReceiverAddresses.length != sendMsgData['amounts'].length) {
      throw Exception(
          "Number of token receivers in config does not match the OP_RETURN outputs");
    }

    // Make sure token inputs == token outputs
    var outputTokenQty = BigInt.from(0);
    sendMsgData['amounts'].forEach((a) => outputTokenQty += a);
    if (tokenInputQty != outputTokenQty) {
      throw Exception("Token input quantity does not match token outputs.");
    }

    // Create a transaction builder
    var transactionBuilder = bitbox.Bitbox.transactionBuilder();
    //  let sequence = 0xffffffff - 1;

    // Calculate the total SLP input amount & add all inputs to the transaction
    var inputSatoshis = BigInt.from(0);
    inputTokenUtxos.forEach((i) {
      inputSatoshis += i['satoshis'];
      transactionBuilder.addInput(i['txid'], i['vout']);
    });

    // Calculate the total BCH input amount & add all inputs to the transaction
    bchInputUtxos.forEach((i) {
      inputSatoshis += BigInt.from(i['satoshis']);
      transactionBuilder.addInput(i['txid'], i['vout']);
    });

    // Start adding outputs to transaction
    // Add SLP SEND OP_RETURN message
    transactionBuilder.addOutput(bitbox.compile(slpSendOpReturn), 0);

    // Add dust outputs associated with tokens
    tokenReceiverAddresses.forEach((outputAddress) {
      outputAddress = bitbox.Address.toLegacyAddress(outputAddress);
      outputAddress = bitbox.Address.toCashAddress(outputAddress);
      transactionBuilder.addOutput(outputAddress, 546);
    });

    // Calculate mining fee cost
    int sendCost = _calculateSendCost(
        slpSendOpReturn.length,
        inputTokenUtxos.length + bchInputUtxos.length,
        tokenReceiverAddresses.length,
        bchChangeAddress: bchChangeReceiverAddress,
        feeRate: extraFee != null ? extraFee : 1);

    // Compute BCH change amount
    BigInt bchChangeAfterFeeSatoshis = inputSatoshis - BigInt.from(sendCost);
    if (bchChangeAfterFeeSatoshis < BigInt.from(0)) {
      return print("Not enough fee to make this transaction");
    }

    // Add change, if any
    if (bchChangeAfterFeeSatoshis > new BigInt.from(546)) {
      transactionBuilder.addOutput(
          bchChangeReceiverAddress, bchChangeAfterFeeSatoshis.toInt());
    }

    // Sign txn and add sig to p2pkh input for convenience if wif is provided,
    // otherwise skip signing.
    int slpIndex = 0;
    inputTokenUtxos.forEach((i) {
      if (!i.containsKey('xpriv')) {
        return throw Exception("Input doesnt contain a xpriv");
      }
      bitbox.ECPair paymentKeyPair =
          bitbox.HDNode.fromXPriv(i['xpriv']).keyPair;
      transactionBuilder.sign(slpIndex, paymentKeyPair, i['satoshis'].toInt(),
          bitbox.Transaction.SIGHASH_ALL);
      slpIndex++;
    });

    int bchIndex = 0;
    for (var i = inputTokenUtxos.length;
        i < inputTokenUtxos.length + bchInputUtxos.length;
        i++) {
      if (!bchInputUtxos[bchIndex].containsKey('xpriv')) {
        return throw Exception("Input doesnt contain a xpriv");
      }
      bitbox.ECPair paymentKeyPair =
          bitbox.HDNode.fromXPriv(bchInputUtxos[bchIndex]['xpriv']).keyPair;
      transactionBuilder.sign(
          i,
          paymentKeyPair,
          bchInputUtxos[bchIndex]['satoshis'].toInt(),
          bitbox.Transaction.SIGHASH_ALL);
      bchIndex++;
    }

    // Build the transaction to hex and return
    // warn user if the transaction was not fully signed
    String hex = transactionBuilder.build().toHex();
    // Check For Low Fee
    int outValue = 0;
    transactionBuilder.tx.outputs.forEach((o) => outValue += o.value);
    int inValue = 0;
    inputTokenUtxos.forEach((i) => inValue += i['satoshis'].toInt());
    bchInputUtxos.forEach((i) => inValue += i['satoshis']);
    if (inValue - outValue < hex.length / 2) {
      throw Exception(
          "Transaction input BCH amount is too low.  Add more BCH inputs to fund this transaction.");
    }
    return hex;
  }

  int _calculateSendCost(int sendOpReturnLength, int inputUtxoSize, int outputs,
      {String bchChangeAddress, int feeRate = 1, bool forTokens = true}) {
    int nonfeeoutputs = 0;
    if (forTokens) {
      nonfeeoutputs = outputs * 546;
    }
    if (bchChangeAddress != null && bchChangeAddress != 'undefined') {
      outputs += 1;
    }
    int fee = bitbox.BitcoinCash.getByteCount(inputUtxoSize, outputs);
    fee += sendOpReturnLength;
    fee += 10; // added to account for OP_RETURN ammount of 0000000000000000
    fee *= feeRate;
    //print("SEND cost before outputs: " + fee.toString());
    fee += nonfeeoutputs;
    //print("SEND cost after outputs are added: " + fee.toString());

    return fee;
  }
}
