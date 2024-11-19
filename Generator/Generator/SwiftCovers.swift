import Foundation
import SwiftParser
import SwiftSyntax

/// Source snippets of Swift that can replace FFI calls to Godot engine methods.
struct SwiftCovers {

    struct Key: Hashable, CustomStringConvertible {
        /// A type name.
        var type: String

        /// A method name, operator, or `init`.
        var name: String

        /// The parameter types.
        var parameterTypes: [String]

        /// The return type.
        var returnType: String

        var description: String {
            "\(type).\(name)(\(parameterTypes.joined(separator: ", "))) -> \(returnType)"
        }
    }

    var covers: [Key: CodeBlockSyntax] = [:]

    /// Load the Swift source files from `sourceDir` and extract snippets usable as method implementations.
    init(sourceDir: URL) {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: sourceDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
            )
        } catch {
            print("warning: couldn't scan folder at \(sourceDir): \(error)")
            return
        }

        for url in urls {
            let source: String
            do {
                source = try String(contentsOf: url, encoding: .utf8)
            } catch {
                print("warning: couldn't read contents of \(url): \(error)")
                continue
            }

            let root = Parser.parse(source: source)

            for statement in root.statements {
                guard
                    let exn = statement.item.as(ExtensionDeclSyntax.self),
                    exn.genericWhereClause == nil,
                    let type = exn.extendedType.as(IdentifierTypeSyntax.self)?.name.text
                else {
                    continue
                }

                for member in exn.memberBlock.members {
                    extractCover(from: member, of: type)
                }
            }
        }
    }

    private mutating func extractCover(from member: MemberBlockItemSyntax, of type: String) {
        if
            let function = member.decl.as(FunctionDeclSyntax.self),
            function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.public) }),
            function.genericWhereClause == nil,
            function.genericParameterClause == nil,
            function.signature.effectSpecifiers == nil
        {
            _ = extractFunctionCover(from: function, of: type)
            || extractBinaryOperatorCover(from: function, of: type)
            return
        }

        if extractInitCover(from: member, of: type) {
            return
        }
    }

    private mutating func extractInitCover(from member: MemberBlockItemSyntax, of type: String) -> Bool {
        guard
            let initer = member.decl.as(InitializerDeclSyntax.self),
            initer.genericWhereClause == nil,
            initer.genericParameterClause == nil,
            case let signature = initer.signature,
            signature.effectSpecifiers == nil,
            case let parameterTypes = signature.parameterClause.parameters
                .compactMap({ $0.type.as(IdentifierTypeSyntax.self)?.name.text }),
            parameterTypes.count == signature.parameterClause.parameters.count,
            let body = initer.body
        else {
            return false
        }

        let key = Key(
            type: type,
            name: "init",
            parameterTypes: parameterTypes,
            returnType: type
        )

        print("found cover for \(key)")

        covers[key] = body

        return true
    }

    private mutating func extractFunctionCover(from function: FunctionDeclSyntax, of type: String) -> Bool {
        guard
            function.modifiers.map({ $0.name.tokenKind }) == [.keyword(.public)],
            case .identifier(let name) = function.name.tokenKind,
            case let signature = function.signature,
            case let parameterTypes = signature.parameterClause.parameters
                .compactMap({ $0.type.as(IdentifierTypeSyntax.self)?.name.text }),
            parameterTypes.count == signature.parameterClause.parameters.count,
            let body = function.body
        else {
            return false
        }

        let returnType: String
        if let returnTypeSx = signature.returnClause?.type.as(IdentifierTypeSyntax.self) {
            returnType = returnTypeSx.name.text
        } else if signature.returnClause == nil {
            returnType = "Void"
        } else {
            print("warning: couldn't handle return type \(signature.returnClause!)")
            return true
        }

        let key = Key(
            type: type,
            name: name,
            parameterTypes: parameterTypes,
            returnType: returnType
        )

        print("found cover for \(key)")
        covers[key] = body
        return true
    }

    private mutating func extractBinaryOperatorCover(from function: FunctionDeclSyntax, of type: String) -> Bool {
        guard
            Set(function.modifiers.map({ $0.name.tokenKind })) == [.keyword(.public), .keyword(.static)],
            case .binaryOperator(let op) = function.name.tokenKind,
            case let signature = function.signature,
            case let parameterTypes = signature.parameterClause.parameters
                .compactMap({ $0.type.as(IdentifierTypeSyntax.self)?.name.text }),
            parameterTypes.count == signature.parameterClause.parameters.count,
            let body = function.body
        else {
            return false
        }

        let returnType: String
        if let returnTypeSx = signature.returnClause?.type.as(IdentifierTypeSyntax.self) {
            returnType = returnTypeSx.name.text
        } else if signature.returnClause == nil {
            returnType = "Void"
        } else {
            print("warning: couldn't handle return type \(signature.returnClause!)")
            return true
        }

        let key = Key(
            type: type,
            name: op,
            parameterTypes: parameterTypes,
            returnType: returnType
        )

        print("found cover for \(key)")
        covers[key] = body
        return true
    }

}
