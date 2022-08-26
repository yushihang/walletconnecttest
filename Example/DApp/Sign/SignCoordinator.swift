import UIKit
import Combine
import WalletConnectSign
import WalletConnectRelay

final class SignCoordinator {

    private var publishers = Set<AnyCancellable>()

    let navigationController = UINavigationController()

    lazy var tabBarItem: UITabBarItem = {
        let item = UITabBarItem()
        item.title = "Sign"
        item.image = UIImage(systemName: "signature")
        return item
    }()

    func start() {
        navigationController.tabBarItem = tabBarItem

        let metadata = AppMetadata(
            name: "Swift Dapp",
            description: "WalletConnect DApp sample",
            url: "wallet.connect",
            icons: ["https://avatars.githubusercontent.com/u/37784886"])

        Sign.configure(metadata: metadata)

        if CommandLine.arguments.contains("-cleanInstall") {
            try? Sign.instance.cleanup()
        }

        Sign.instance.sessionDeletePublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in
                showSelectChainScreen()
            }.store(in: &publishers)

        Sign.instance.sessionResponsePublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] response in
                presentResponse(for: response)
            }.store(in: &publishers)

        if let session = Sign.instance.getSessions().first {
            showAccountsScreen(session)
        } else {
            showSelectChainScreen()
        }
    }

    private func showSelectChainScreen() {
        let controller = SelectChainViewController()
        controller.onSessionSettled = { [unowned self] session in
            showAccountsScreen(session)
        }
        navigationController.viewControllers = [controller]
    }

    private func showAccountsScreen(_ session: Session) {
        let controller = AccountsViewController(session: session)
        controller.onDisconnect = { [unowned self]  in
            showSelectChainScreen()
        }
        navigationController.viewControllers = [controller]
    }

    private func presentResponse(for response: Response) {
        let controller = UINavigationController(rootViewController: ResponseViewController(response: response))
        navigationController.present(controller, animated: true, completion: nil)
    }
}