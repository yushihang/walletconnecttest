import UIKit
import Combine

import WalletConnectSign
import Web3

final class SessionAccountPresenter: ObservableObject {
    enum Errors: Error {
        case notImplemented
    }
    
    @Published var showResponse = false
    @Published var showError = false
    @Published var errorMessage = String.empty
    @Published var showRequestSent = false
    @Published var requesting = false
    var lastRequest: Request?


    private let interactor: SessionAccountInteractor
    private let router: SessionAccountRouter
    private let session: Session
    
    var sessionAccount: AccountDetails
    var response: Response?
    var signedTransactionHex: String = ""
    
    private var subscriptions = Set<AnyCancellable>()
    

    init(
        interactor: SessionAccountInteractor,
        router: SessionAccountRouter,
        sessionAccount: AccountDetails,
        session: Session
    ) {
        defer { setupInitialState() }
        self.interactor = interactor
        self.router = router
        self.sessionAccount = sessionAccount
        self.session = session
    }
    
    func onAppear() {}
    
    func onMethod(method: String) async {
        do {
            let requestParams = try await getRequest(for: method)
            
            let ttl: TimeInterval = 300
            let request = try Request(topic: session.topic, method: method, params: requestParams, chainId: Blockchain(sessionAccount.chain)!, ttl: ttl)
            Task {
                do {
                    ActivityIndicatorManager.shared.start()
                    try await Sign.instance.request(params: request)
                    lastRequest = request
                    ActivityIndicatorManager.shared.stop()
                    requesting = true
                    DispatchQueue.main.async { [weak self] in
                        self?.openWallet()
                    }
                } catch {
                    ActivityIndicatorManager.shared.stop()
                    requesting = false
                    showError.toggle()
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            showError.toggle()
            errorMessage = error.localizedDescription
        }
    }
    
    func copyUri() {
        UIPasteboard.general.string = sessionAccount.account
    }


    func copyResponse(response: Response) {
        switch response.result {
        case  .response(let response):
            UIPasteboard.general.string = try! response.get(String.self).description


        case .error(let error):
            UIPasteboard.general.string = error.message
        }

    }
}

extension String {
    func removingQuotes() -> String {
        var result = self
        if result.hasPrefix("\"") {
            result.removeFirst()
        }
        if result.hasSuffix("\"") {
            result.removeLast()
        }
        return result
    }
}


// MARK: - Private functions
extension SessionAccountPresenter {
    private func setupInitialState() {
        Sign.instance.sessionResponsePublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] response in
                requesting = false
                presentResponse(response: response)
                if let lastRequest, lastRequest.method == "eth_signTransaction" {
                    do {
                        signedTransactionHex = try response.result.asJSONEncodedString()
                        signedTransactionHex = signedTransactionHex.removingQuotes()
                    }
                    catch {
                        signedTransactionHex = ""
                    }
                    print(response)
                }
            }
            .store(in: &subscriptions)
    }
    
    private func getRequest(for method: String) async throws -> AnyCodable {
        let account = session.namespaces.first!.value.accounts.first!.address

        switch method {
        case "eth_sendTransaction":
            let tx = Stub.tx(account: account)
            return AnyCodable(tx)
        case "personal_sign":
            return AnyCodable(["0x4d7920656d61696c206973206a6f686e40646f652e636f6d202d2031363533333933373535313531", account])
        case "eth_signTypedData":
            return AnyCodable([account, Stub.eth_signTypedData])
        case "eth_signTransaction":
            return await AnyCodable(Stub.signTransaction(account:account))
        case "eth_sendRawTransaction":
            return AnyCodable([signedTransactionHex])
        case "eth_sign":
            return AnyCodable([account, "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"])
        default:
            throw Errors.notImplemented
        }


    }
    
    private func presentResponse(response: Response) {
        self.response = response
        DispatchQueue.main.async {
            self.showResponse = true
        }
        
    }
    
    private func openWallet() {
        if let nativeUri = session.peer.redirect?.native {
            UIApplication.shared.open(URL(string: "\(nativeUri)wc?requestSent")!)
        } else {
            showRequestSent.toggle()
        }
    }
}

// MARK: - SceneViewModel
extension SessionAccountPresenter: SceneViewModel {}

// MARK: Errors
extension SessionAccountPresenter.Errors: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notImplemented:   return "Requested method is not implemented"
        }
    }
}

extension Int {
    func toHex() -> String {
        return String(format: "0x%02X", self)
    }
}

// MARK: - Transaction Stub
private enum Stub {
    private static let web3 = Web3(rpcURL: "https://rpc-amoy.polygon.technology/")
    
    private static let destAddr = "0x21669cd5cd7874af2a8e569da3d7a0f6f85e6b4b"
    private static let transferValue = 12345678

    struct Transaction: Codable {
        let from, to, data, gas: String
        let gasPrice, value: String
    }
    
    struct SignTransactionS: Codable {
        let from, to, data, gas: String
        let gasPrice, value, nonce: String
    }
    
    static func tx(account: String) -> [Transaction] {
        [Transaction(from: account,
                     to: destAddr,
                     data: "",//"0xd46e8dd67c5d32be8d46e8dd67c5d32be8058bb8eb970870f072445675058bb8eb970870f072445675",
                     gas: "", //"0x10000",
                     gasPrice: "", //"0x2710",//"0x9184e72a000",
                     value: transferValue.toHex())]
    }
    
    static func getTransactionCountAsync(address: EthereumAddress, block: EthereumQuantityTag = .latest) async -> EthereumQuantity {
        return await withCheckedContinuation { continuation in
            web3.eth.getTransactionCount(address: address, block: block) { result in
                switch result.status {
                case .success(let count):
                    continuation.resume(returning: count)
                case .failure(let error):
                    print("Failed to get transaction count: \(error)")
                    continuation.resume(returning: EthereumQuantity(0))
                }
            }
        }
    }
    
    static func gasPriceAsync() async -> EthereumQuantity {
        return await withCheckedContinuation { continuation in
            web3.eth.gasPrice { result in
                switch result.status {
                case .success(let price):
                    continuation.resume(returning: price)
                case .failure(let error):
                    print("Failed to get gas price: \(error)")
                    continuation.resume(returning: EthereumQuantity(0))
                }
            }
        }
    }
    
    static func estimateGasAsync(call: EthereumCall) async -> EthereumQuantity {
        return await withCheckedContinuation { continuation in
            web3.eth.estimateGas(call: call) { result in
                switch result.status {
                case .success(let gas):
                    continuation.resume(returning: gas)
                case .failure(let error):
                    print("Failed to estimate gas: \(error)")
                    continuation.resume(returning: EthereumQuantity(0))
                }
            }
        }
    }
    
    static func signTransaction(account: String) async -> [SignTransactionS] {
        
        guard let ethAddress = try? EthereumAddress(hex: account, eip55: false) else {
            return []
        }
        guard let destAddress = try? EthereumAddress(hex: destAddr, eip55: false) else {
            return []
        }
        guard let value = try? EthereumQuantity(ethereumValue: EthereumValue.string(transferValue.toHex())) else {
            return []
        }
        let nonce = await getTransactionCountAsync(address: ethAddress)
        let gasPrice = await gasPriceAsync()
        let call = EthereumCall(from: ethAddress, to: destAddress, gas: nil, gasPrice: gasPrice, value: value, data: nil)
        let gas = await estimateGasAsync(call: call)
        return [SignTransactionS(
            from: account,
            to: destAddr,
            data: "",//"0xd46e8dd67c5d32be8d46e8dd67c5d32be8058bb8eb970870f072445675058bb8eb970870f072445675",
            gas: gas.hex(), //"0x10000",
            gasPrice: gasPrice.hex(), //"0x2710",//"0x9184e72a000",
            value: transferValue.toHex(),
            nonce: nonce.hex()
        )]
        /*
    static let tx = [Transaction(from: "0x52f203bc8bc838e666548b7e0c8ffd54ce3da615",
                                to: "0x21669cd5cd7874af2a8e569da3d7a0f6f85e6b4b",
                                data: "",//"0xd46e8dd67c5d32be8d46e8dd67c5d32be8058bb8eb970870f072445675058bb8eb970870f072445675",
                                gas: "", //"0x10000",
                                gasPrice: "", //"0x2710",//"0x9184e72a000",
                                value: "0x9184e72a" //,
                                 /*nonce: "0x117"*/)]
    
    private static let signTransaction_ = [SignTransactionS(from: "0x52f203bc8bc838e666548b7e0c8ffd54ce3da615",
                                 to: "0x21669cd5cd7874af2a8e569da3d7a0f6f85e6b4b",
                                 data: "",//"0xd46e8dd67c5d32be8d46e8dd67c5d32be8058bb8eb970870f072445675058bb8eb970870f072445675",
                                 gas: "", //"0x10000",
                                 gasPrice: "", //"0x2710",//"0x9184e72a000",
                                 value: "0x9184e72a",
                                 nonce: "0x117")]
    
    static var signTransaction: [SignTransactionS] {
        [SignTransactionS(from: "0x52f203bc8bc838e666548b7e0c8ffd54ce3da615",
                          to: "0x21669cd5cd7874af2a8e569da3d7a0f6f85e6b4b",
                          data: "",//"0xd46e8dd67c5d32be8d46e8dd67c5d32be8058bb8eb970870f072445675058bb8eb970870f072445675",
                          gas: "", //"0x10000",
                          gasPrice: "", //"0x2710",//"0x9184e72a000",
                          value: "0x9184e72a",
                          nonce: "0x118")]
    */
    }
    
    static let eth_signTypedData = """
{
"types": {
    "EIP712Domain": [
        {
            "name": "name",
            "type": "string"
        },
        {
            "name": "version",
            "type": "string"
        },
        {
            "name": "chainId",
            "type": "uint256"
        },
        {
            "name": "verifyingContract",
            "type": "address"
        }
    ],
    "Person": [
        {
            "name": "name",
            "type": "string"
        },
        {
            "name": "wallet",
            "type": "address"
        }
    ],
    "Mail": [
        {
            "name": "from",
            "type": "Person"
        },
        {
            "name": "to",
            "type": "Person"
        },
        {
            "name": "contents",
            "type": "string"
        }
    ]
},
"primaryType": "Mail",
"domain": {
    "name": "Ether Mail",
    "version": "1",
    "chainId": 80002,
    "verifyingContract": "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"
},
"message": {
    "from": {
        "name": "Cow",
        "wallet": "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"
    },
    "to": {
        "name": "Bob",
        "wallet": "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"
    },
    "contents": "Hello, Bob!"
}
}
"""
}
