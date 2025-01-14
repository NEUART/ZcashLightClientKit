//
//  SynchronizerOfflineTests.swift
//  
//
//  Created by Michal Fousek on 23.03.2023.
//

import Combine
import Foundation
@testable import TestUtils
import XCTest
@testable import ZcashLightClientKit

class SynchronizerOfflineTests: XCTestCase {
    let data = AlternativeSynchronizerAPITestsData()
    var network: ZcashNetwork!
    var cancellables: [AnyCancellable] = []

    override func setUp() async throws {
        try await super.setUp()
        network = ZcashNetworkBuilder.network(for: .testnet)
        cancellables = []
    }

    override func tearDown() async throws {
        try await super.tearDown()
        network = nil
        cancellables = []
    }

    func testCallPrepareWithAlreadyUsedAliasThrowsError() async throws {
        let firstTestCoordinator = try await TestCoordinator(
            alias: .custom("alias"),
            walletBirthday: 10,
            network: network,
            callPrepareInConstructor: false
        )

        let secondTestCoordinator = try await TestCoordinator(
            alias: .custom("alias"),
            walletBirthday: 10,
            network: network,
            callPrepareInConstructor: false
        )

        do {
            _ = try await firstTestCoordinator.prepare(seed: Environment.seedBytes)
        } catch {
            XCTFail("Unpected fail. Prepare should succeed. \(error)")
        }

        do {
            _ = try await secondTestCoordinator.prepare(seed: Environment.seedBytes)
            XCTFail("Prepare should fail.")
        } catch { }
    }

    func testWhenSynchronizerIsDeallocatedAliasIsntUsedAnymore() async throws {
        var testCoordinator: TestCoordinator! = try await TestCoordinator(
            alias: .default,
            walletBirthday: 10,
            network: network,
            callPrepareInConstructor: false
        )

        do {
            _ = try await testCoordinator.prepare(seed: Environment.seedBytes)
        } catch {
            XCTFail("Unpected fail. Prepare should succeed. \(error)")
        }

        testCoordinator = try await TestCoordinator(
            alias: .default,
            walletBirthday: 10,
            network: network,
            callPrepareInConstructor: false
        )

        do {
            _ = try await testCoordinator.prepare(seed: Environment.seedBytes)
        } catch {
            XCTFail("Unpected fail. Prepare should succeed. \(error)")
        }
    }

    func testCallWipeWithAlreadyUsedAliasThrowsError() async throws {
        let firstTestCoordinator = try await TestCoordinator(alias: .default, walletBirthday: 10, network: network, callPrepareInConstructor: false)
        let secondTestCoordinator = try await TestCoordinator(alias: .default, walletBirthday: 10, network: network, callPrepareInConstructor: false)

        let firstWipeExpectation = XCTestExpectation(description: "First wipe expectation")

        firstTestCoordinator.synchronizer.wipe()
            .sink(
                receiveCompletion: { result in
                    switch result {
                    case .finished:
                        firstWipeExpectation.fulfill()
                    case let .failure(error):
                        XCTFail("Unexpected error when calling wipe \(error)")
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [firstWipeExpectation], timeout: 1)

        let secondWipeExpectation = XCTestExpectation(description: "Second wipe expectation")

        secondTestCoordinator.synchronizer.wipe()
            .sink(
                receiveCompletion: { result in
                    switch result {
                    case .finished:
                        XCTFail("Second wipe should fail with error.")
                    case let .failure(error):
                        if let error = error as? InitializerError, case .aliasAlreadyInUse = error {
                            secondWipeExpectation.fulfill()
                        } else {
                            XCTFail("Wipe failed with unexpected error: \(error)")
                        }
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [secondWipeExpectation], timeout: 1)
    }

    func testPrepareCanBeCalledAfterWipeWithSameInstanceOfSDKSynchronizer() async throws {
        let testCoordinator = try await TestCoordinator(alias: .default, walletBirthday: 10, network: network, callPrepareInConstructor: false)

        let expectation = XCTestExpectation(description: "Wipe expectation")

        testCoordinator.synchronizer.wipe()
            .sink(
                receiveCompletion: { result in
                    switch result {
                    case .finished:
                        expectation.fulfill()
                    case let .failure(error):
                        XCTFail("Unexpected error when calling wipe \(error)")
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1)

        do {
            _ = try await testCoordinator.prepare(seed: Environment.seedBytes)
        } catch {
            XCTFail("Prepare after wipe should succeed.")
        }
    }

    func testSendToAddressCalledWithoutPrepareThrowsError() async throws {
        let testCoordinator = try await TestCoordinator(alias: .default, walletBirthday: 10, network: network, callPrepareInConstructor: false)

        do {
            _ = try await testCoordinator.synchronizer.sendToAddress(
                spendingKey: testCoordinator.spendingKey,
                zatoshi: Zatoshi(1),
                toAddress: .transparent(data.transparentAddress),
                memo: nil
            )
            XCTFail("Send to address should fail.")
        } catch {
            if let error = error as? SynchronizerError, case .notPrepared = error {
            } else {
                XCTFail("Send to address failed with unexpected error: \(error)")
            }
        }
    }

    func testShieldFundsCalledWithoutPrepareThrowsError() async throws {
        let testCoordinator = try await TestCoordinator(alias: .default, walletBirthday: 10, network: network, callPrepareInConstructor: false)

        do {
            _ = try await testCoordinator.synchronizer.shieldFunds(
                spendingKey: testCoordinator.spendingKey,
                memo: Memo(string: "memo"),
                shieldingThreshold: Zatoshi(1)
            )
            XCTFail("Shield funds should fail.")
        } catch {
            if let error = error as? SynchronizerError, case .notPrepared = error {
            } else {
                XCTFail("Shield funds failed with unexpected error: \(error)")
            }
        }
    }

    func testRefreshUTXOCalledWithoutPrepareThrowsError() async throws {
        let testCoordinator = try await TestCoordinator(alias: .default, walletBirthday: 10, network: network, callPrepareInConstructor: false)

        do {
            _ = try await testCoordinator.synchronizer.refreshUTXOs(address: data.transparentAddress, from: 1)
            XCTFail("Shield funds should fail.")
        } catch {
            if let error = error as? SynchronizerError, case .notPrepared = error {
            } else {
                XCTFail("Shield funds failed with unexpected error: \(error)")
            }
        }
    }

    func testRewindCalledWithoutPrepareThrowsError() async throws {
        let testCoordinator = try await TestCoordinator(alias: .default, walletBirthday: 10, network: network, callPrepareInConstructor: false)

        let expectation = XCTestExpectation()

        testCoordinator.synchronizer.rewind(.quick)
            .sink(
                receiveCompletion: { result in
                    switch result {
                    case .finished:
                        XCTFail("Rewind should fail with error.")
                    case let .failure(error):
                        if let error = error as? SynchronizerError, case .notPrepared = error {
                            expectation.fulfill()
                        } else {
                            XCTFail("Rewind failed with unexpected error: \(error)")
                        }
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1)
    }

    func testURLsParsingFailsInInitialierPrepareThenThrowsError() async throws {
        let validFileURL = URL(fileURLWithPath: "/some/valid/path/to.file")
        let validDirectoryURL = URL(fileURLWithPath: "/some/valid/path/to/directory")
        let invalidPathURL = URL(string: "https://whatever")!

        let initializer = Initializer(
            cacheDbURL: nil,
            fsBlockDbRoot: validDirectoryURL,
            dataDbURL: validFileURL,
            pendingDbURL: invalidPathURL,
            endpoint: LightWalletEndpointBuilder.default,
            network: ZcashNetworkBuilder.network(for: .testnet),
            spendParamsURL: validFileURL,
            outputParamsURL: validFileURL,
            saplingParamsSourceURL: .default,
            alias: .default,
            logLevel: .debug
        )

        XCTAssertNotNil(initializer.urlsParsingError)

        let synchronizer = SDKSynchronizer(initializer: initializer)

        do {
            let derivationTool = DerivationTool(networkType: network.networkType)
            let spendingKey = try derivationTool.deriveUnifiedSpendingKey(
                seed: Environment.seedBytes,
                accountIndex: 0
            )
            let viewingKey = try derivationTool.deriveUnifiedFullViewingKey(from: spendingKey)
            _ = try await synchronizer.prepare(with: Environment.seedBytes, viewingKeys: [viewingKey], walletBirthday: 123000)
            XCTFail("Failure of prepare is expected.")
        } catch {
            if let error = error as? InitializerError, case let .cantUpdateURLWithAlias(failedURL) = error {
                XCTAssertEqual(failedURL, invalidPathURL)
            } else {
                XCTFail("Failed with unexpected error: \(error)")
            }
        }
    }

    func testURLsParsingFailsInInitialierWipeThenThrowsError() async throws {
        let validFileURL = URL(fileURLWithPath: "/some/valid/path/to.file")
        let validDirectoryURL = URL(fileURLWithPath: "/some/valid/path/to/directory")
        let invalidPathURL = URL(string: "https://whatever")!

        let initializer = Initializer(
            cacheDbURL: nil,
            fsBlockDbRoot: validDirectoryURL,
            dataDbURL: validFileURL,
            pendingDbURL: invalidPathURL,
            endpoint: LightWalletEndpointBuilder.default,
            network: ZcashNetworkBuilder.network(for: .testnet),
            spendParamsURL: validFileURL,
            outputParamsURL: validFileURL,
            saplingParamsSourceURL: .default,
            alias: .default,
            logLevel: .debug
        )

        XCTAssertNotNil(initializer.urlsParsingError)

        let synchronizer = SDKSynchronizer(initializer: initializer)
        let expectation = XCTestExpectation()

        synchronizer.wipe()
            .sink(
                receiveCompletion: { result in
                    switch result {
                    case .finished:
                        XCTFail("Failure of wipe is expected.")
                    case let .failure(error):
                        if let error = error as? InitializerError, case let .cantUpdateURLWithAlias(failedURL) = error {
                            XCTAssertEqual(failedURL, invalidPathURL)
                            expectation.fulfill()
                        } else {
                            XCTFail("Failed with unexpected error: \(error)")
                        }
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1)
    }
}
