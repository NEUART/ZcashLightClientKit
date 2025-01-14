//
//  SaplingParameterDownloader.swift
//  ZcashLightClientKit
//
//  Created by Francisco Gindre on 10/7/20.
//

import Foundation
import CryptoKit

/// Small utility that converts Digest to the String
extension Digest {
    var bytes: [UInt8] { Array(makeIterator()) }
    var data: Data { Data(bytes) }

    var hexString: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Helper class to handle the download of Sapling parameters
public enum SaplingParameterDownloader {
    public enum Errors: Error {
        case failed(error: Error)
        case spendParamsInvalidSHA1
        case outputParamsInvalidSHA1
    }

    /// Download a Spend parameter from default host and stores it at given URL
    /// - Parameters:
    ///     - at: The destination URL for the download
    @discardableResult
    public static func downloadSpendParameter(_ at: URL, sourceURL: URL, logger: Logger) async throws -> URL {
        let resultURL = try await downloadFileWithRequestWithContinuation(URLRequest(url: sourceURL), logger: logger, at: at)
        try isSpendParamsSHA1Valid(url: resultURL)
        return resultURL
    }
    
    /// Download an Output parameter from default host and stores it at given URL
    /// - Parameters:
    ///     - at: The destination URL for the download
    @discardableResult
    public static func downloadOutputParameter(_ at: URL, sourceURL: URL, logger: Logger) async throws -> URL {
        let resultURL = try await downloadFileWithRequestWithContinuation(URLRequest(url: sourceURL), logger: logger, at: at)
        try isOutputParamsSHA1Valid(url: resultURL)
        return resultURL
    }

    /// Downloads the parameters if not present and provides the resulting URLs for both parameters
    /// - Parameters:
    ///     - spendURL: URL to check whether the parameter is already downloaded
    ///     - outputURL: URL to check whether the parameter is already downloaded
    @discardableResult
    public static func downloadParamsIfnotPresent(
        spendURL: URL,
        spendSourceURL: URL,
        outputURL: URL,
        outputSourceURL: URL,
        logger: Logger
    ) async throws -> (spend: URL, output: URL) {
        do {
            async let spendResultURL = ensureSpendParameter(at: spendURL, sourceURL: spendSourceURL, logger: logger)
            async let outputResultURL = ensureOutputParameter(at: outputURL, sourceURL: outputSourceURL, logger: logger)
            
            let results = try await [spendResultURL, outputResultURL]
            return (spend: results[0], output: results[1])
        } catch {
            throw Errors.failed(error: error)
        }
    }
        
    static func ensureSpendParameter(at url: URL, sourceURL: URL, logger: Logger) async throws -> URL {
        if isFilePresent(url: url) {
            try isSpendParamsSHA1Valid(url: url)
            return url
        } else {
            return try await downloadSpendParameter(url, sourceURL: sourceURL, logger: logger)
        }
    }
    
    static func ensureOutputParameter(at url: URL, sourceURL: URL, logger: Logger) async throws -> URL {
        if isFilePresent(url: url) {
            try isOutputParamsSHA1Valid(url: url)
            return url
        } else {
            return try await downloadOutputParameter(url, sourceURL: sourceURL, logger: logger)
        }
    }
    
    static func isFilePresent(url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
    
    static func isSpendParamsSHA1Valid(url: URL) throws {
        if Insecure.SHA1.hash(data: try Data(contentsOf: url)).hexString != Constants.spendParamFileSHA1 {
            try FileManager.default.removeItem(at: url)
            throw Errors.spendParamsInvalidSHA1
        }
    }

    static func isOutputParamsSHA1Valid(url: URL) throws {
        if Insecure.SHA1.hash(data: try Data(contentsOf: url)).hexString != Constants.outputParamFileSHA1 {
            try FileManager.default.removeItem(at: url)
            throw Errors.outputParamsInvalidSHA1
        }
    }
}

private extension SaplingParameterDownloader {
    enum Constants {
        public static let spendParamFileSHA1 = "a15ab54c2888880e53c823a3063820c728444126"
        public static let outputParamFileSHA1 = "0ebc5a1ef3653948e1c46cf7a16071eac4b7e352"
    }

    static func downloadFileWithRequestWithContinuation(
    _ request: URLRequest,
    logger: Logger,
    at destination: URL
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            downloadFileWithRequest(request, at: destination, logger: logger) { result in
                switch result {
                case .success(let outputResultURL):
                    continuation.resume(returning: outputResultURL)
                case .failure(let outputResultError):
                    continuation.resume(throwing: outputResultError)
                }
            }
        }
    }

    static func downloadFileWithRequest(
        _ request: URLRequest,
        at destination: URL,
        logger: Logger,
        result: @escaping (Result<URL, Error>) -> Void
    ) {
        logger.debug("Downloading sapling file from \(String(describing: request.url))")
        let task = URLSession.shared.downloadTask(with: request) { url, _, error in
            if let error {
                result(.failure(Errors.failed(error: error)))
                return
            } else if let localUrl = url {
                do {
                    try FileManager.default.moveItem(at: localUrl, to: destination)
                    result(.success(destination))
                } catch {
                    result(.failure(error))
                }
            }
        }

        task.resume()
    }
}
