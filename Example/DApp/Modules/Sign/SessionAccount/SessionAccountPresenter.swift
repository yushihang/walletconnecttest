import UIKit
import Combine

import WalletConnectSign

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
    
    func onMethod(method: String) {
        do {
            let requestParams = try getRequest(for: method)
            
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


    func copyResponse() {
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
    
    private func getRequest(for method: String) throws -> AnyCodable {
        let account = session.namespaces.first!.value.accounts.first!.address
        if method == "eth_sendTransaction" {
            let tx = Stub.tx
            return AnyCodable(tx)
        } else if method == "personal_sign" {
            return AnyCodable(["0x4d7920656d61696c206973206a6f686e40646f652e636f6d202d2031363533333933373535313531", account])
        } else if method == "eth_signTypedData" {
            return AnyCodable([account, Stub.eth_signTypedData])
        } else if method == "eth_signTransaction" {
            return AnyCodable(Stub.signTransaction)
        } else if method == "eth_sendRawTransaction" {
            return AnyCodable([signedTransactionHex])
        }
        throw Errors.notImplemented
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

// MARK: - Transaction Stub
private enum Stub {
    struct Transaction: Codable {
        let from, to, data, gas: String
        let gasPrice, value: String
    }
    
    struct SignTransactionS: Codable {
        let from, to, data, gas: String
        let gasPrice, value, nonce: String
    }
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
