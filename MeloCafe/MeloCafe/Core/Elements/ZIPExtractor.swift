//
//  ZIPExtractor.swift
//  MeloCafe
//
//  Created by Stossy11 on 11/4/2026.
//

import Foundation
import Compression

enum ZIPExtractor {
    enum ZIPError: Error, LocalizedError {
        case invalidArchive
        case unsupportedCompression(UInt16)
        case decompressionFailed
        case corruptEntry(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidArchive: return "Invalid ZIP archive"
            case .unsupportedCompression(let m): return "Unsupported compression method \(m)"
            case .decompressionFailed: return "Decompression failed"
            case .corruptEntry(let name): return "Corrupt entry: \(name)"
            }
        }
    }
    
    static func extract(zipURL: URL, to destinationURL: URL) throws {
        let data = try Data(contentsOf: zipURL)
        try extract(data: data, to: destinationURL)
    }
    
    static func extract(data: Data, to destinationURL: URL) throws {
        let fm = FileManager.default
        
        try data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let basePtr = rawBuffer.baseAddress else { throw ZIPError.invalidArchive }
            let totalSize = rawBuffer.count
            
            guard let eocdOffset = findEOCD(in: basePtr, size: totalSize) else {
                throw ZIPError.invalidArchive
            }
            
            let eocd = basePtr + eocdOffset
            let centralDirOffset = Int(readUInt32(eocd + 16))
            let entryCount = Int(readUInt16(eocd + 10))
            
            var offset = centralDirOffset
            
            for _ in 0..<entryCount {
                guard offset + 46 <= totalSize else { throw ZIPError.invalidArchive }
                let entry = basePtr + offset
                
                guard readUInt32(entry) == 0x02014b50 else { throw ZIPError.invalidArchive }
                
                let compressionMethod = readUInt16(entry + 10)
                let compressedSize = Int(readUInt32(entry + 20))
                let uncompressedSize = Int(readUInt32(entry + 24))
                let nameLength = Int(readUInt16(entry + 28))
                let extraLength = Int(readUInt16(entry + 30))
                let commentLength = Int(readUInt16(entry + 32))
                let localHeaderOffset = Int(readUInt32(entry + 42))
                
                let nameData = Data(bytes: entry + 46, count: nameLength)
                guard let name = String(data: nameData, encoding: .utf8) else {
                    offset += 46 + nameLength + extraLength + commentLength
                    continue
                }
                
                if name.contains("../") || name.contains("..\\") {
                    offset += 46 + nameLength + extraLength + commentLength
                    continue
                }
                
                let entryURL = destinationURL.appendingPathComponent(name)
                
                if name.hasSuffix("/") {
                    // Directory
                    try fm.createDirectory(at: entryURL, withIntermediateDirectories: true)
                } else if uncompressedSize > 0 {
                    // File
                    guard localHeaderOffset + 30 <= totalSize else {
                        throw ZIPError.corruptEntry(name)
                    }
                    let localHeader = basePtr + localHeaderOffset
                    guard readUInt32(localHeader) == 0x04034b50 else {
                        throw ZIPError.corruptEntry(name)
                    }
                    let localNameLen = Int(readUInt16(localHeader + 26))
                    let localExtraLen = Int(readUInt16(localHeader + 28))
                    let fileDataOffset = localHeaderOffset + 30 + localNameLen + localExtraLen
                    
                    guard fileDataOffset + compressedSize <= totalSize else {
                        throw ZIPError.corruptEntry(name)
                    }
                    
                    let compressedData = UnsafeRawPointer(basePtr + fileDataOffset)
                    
                    let fileData: Data
                    switch compressionMethod {
                    case 0: // Store
                        fileData = Data(bytes: compressedData, count: uncompressedSize)
                    case 8: // Deflate
                        fileData = try inflate(
                            src: compressedData,
                            srcSize: compressedSize,
                            dstSize: uncompressedSize
                        )
                    default:
                        throw ZIPError.unsupportedCompression(compressionMethod)
                    }
                    
                    try fm.createDirectory(
                        at: entryURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fileData.write(to: entryURL)
                }
                
                offset += 46 + nameLength + extraLength + commentLength
            }
        }
    }
    
    private static func inflate(src: UnsafeRawPointer, srcSize: Int, dstSize: Int) throws -> Data {
        var dstBuffer = Data(count: dstSize)
        
        let result = dstBuffer.withUnsafeMutableBytes { dstRaw -> Int in
            guard let dstPtr = dstRaw.baseAddress?.bindMemory(to: UInt8.self, capacity: dstSize) else {
                return 0
            }
            let srcPtr = src.bindMemory(to: UInt8.self, capacity: srcSize)
            
            let decodedSize = compression_decode_buffer(
                dstPtr, dstSize,
                srcPtr, srcSize,
                nil,
                COMPRESSION_ZLIB
            )
            return decodedSize
        }
        
        guard result == dstSize else { throw ZIPError.decompressionFailed }
        return dstBuffer
    }
    
    private static func findEOCD(in ptr: UnsafeRawPointer, size: Int) -> Int? {
        let minOffset = max(0, size - 65557)
        for i in stride(from: size - 22, through: minOffset, by: -1) {
            if readUInt32(ptr + i) == 0x06054b50 {
                return i
            }
        }
        return nil
    }
    
    private static func readUInt16(_ ptr: UnsafeRawPointer) -> UInt16 {
        ptr.loadUnaligned(as: UInt16.self).littleEndian
    }
    
    private static func readUInt32(_ ptr: UnsafeRawPointer) -> UInt32 {
        ptr.loadUnaligned(as: UInt32.self).littleEndian
    }
}
