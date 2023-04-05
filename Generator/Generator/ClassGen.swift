//
//  ClassGen.swift
//  Generator
//
//  Created by Miguel de Icaza on 3/26/23.
//
// Need support for:
//   enum::
//   typedarray::
//   bitfield::

import Foundation

// Populated with the types loaded from the api.json, we assume they are all reference types
// anything else is not
var referenceTypes: [String:Bool] = [:]

// Maps a typename to its toplevel Json element
var tree: [String: JGodotExtensionAPIClass] = [:]

var typeToChildren: [String:[String]] = [:]

func makeDefaultInit (godotType: String, initCollection: String = "") -> String {
    switch godotType {
    case "int":
        return "0"
    case "float":
        return "0.0"
    case "bool":
        return "false"
    case "String":
        return "GString ()"
    case "Array":
        return "GArray ()"
    case let t where t.starts (with: "typedarray::"):
        let simple = SimpleType(type: String (t.dropFirst(12)))
        return "GodotCollection<\(getGodotType (simple))>(\(initCollection))"
    case "enum::Error":
        return ".ok"
    case "enum::Variant.Type":
        return ".`nil`"
    case let e where e.starts (with: "enum::"):
        return "\(e.dropFirst(6))(rawValue: 0)!"
    case let e where e.starts (with: "bitfield::"):
        let simple = SimpleType (type: godotType, meta: nil)
        return "\(getGodotType (simple)) ()"
   
    case let other where builtinGodotTypeNames.contains(other):
        return "\(godotType) ()"
    case "void*":
        return "nil"
    default:
        if isCoreType(name: godotType) {
            return "\(getGodotType(SimpleType (type: godotType))) ()"
        } else {
            return "\(getGodotType(SimpleType (type: godotType))) (fast: true)"
        }
    }
}

func makeDefaultReturn (godotType: String) -> String {
    return "return \(makeDefaultInit(godotType: godotType))"
}

func argTypeNeedsCopy (godotType: String) -> Bool {
    if isStructMap [godotType] ?? false {
        return true
    }
    if godotType.starts(with: "enum::") {
        return true
    }
    if godotType.starts(with: "bitfield::") {
        return true
    }
    return false
}

func generateVirtualProxy (cdef: JGodotExtensionAPIClass, methodName: String, method: JGodotClassMethod) {
    // Generate the glue for the virtual methods (those that start with an underscore in Godot
    guard method.isVirtual else {
        print ("ERROR: internally, we passed methods that are not virtual")
        return
    }
    let virtRet: String?
    if let ret = method.returnValue {
        virtRet = getGodotType(ret)
    } else {
        virtRet = nil
    }
    b ("func _\(cdef.name)_proxy\(method.name) (instance: UnsafeMutableRawPointer?, args: UnsafePointer<UnsafeRawPointer?>?, retPtr: UnsafeMutableRawPointer?)") {
        p ("guard let instance else { return }")
        p ("guard let args else { return }")
        p ("let swiftObject = Unmanaged<\(cdef.name)>.fromOpaque(instance).takeUnretainedValue()")
        
        var argCall = ""
        var i = 0
        for arg in method.arguments ?? [] {
            if argCall != "" { argCall += ", " }
            let argName = escapeSwift (snakeToCamel (arg.name))
            argCall += "\(argName): "
            if arg.type == "String" {
                argCall += "stringFromGodotString (args [\(i)]!)"
            } else if isStructMap [arg.type] ?? false == false && builtinSizes [arg.type] == nil {
                //
                // This idiom guarantees that: if this is a known object, we surface this
                // object, but if it is not known, then we create the instance
                //
                argCall += "lookupLiveObject (handleAddress: args [\(i)]!) as? \(arg.type) ?? \(arg.type) (nativeHandle: args [\(i)]!)"
            } else {
                let gt = getGodotType(arg)
                argCall += "args [\(i)]!.assumingMemoryBound (to: \(gt).self).pointee"
            }
            i += 1
        }
        let hasReturn = method.returnValue != nil
        p ("\(hasReturn ? "let ret = " : "")swiftObject.\(methodName) (\(argCall))")
        if let ret = method.returnValue {
            if ret.type == "Material" {
                print ("here")
            }
            if isStructMap [ret.type] ?? false || isStructMap [virtRet ?? "NON_EXIDTENT"] ?? false || ret.type.starts(with: "enum::") || ret.type.starts(with: "bitfield::"){
                p ("retPtr!.storeBytes (of: ret, as: \(virtRet!).self)")
            } else {
                let target = classMap [ret.type] != nil ? "handle" : "content"
                p ("retPtr!.storeBytes (of: ret.\(target), as: type (of: ret.\(target)))")
            }
        }
        //let original = Unmanaged<GDExample>.fromOpaque(instance).takeUnretainedValue()
        //let first = args![0]!
        //original._process(delta: first.assumingMemoryBound(to: Double.self).pointee)

    }
}

///
/// Returns a hashtable mapping a godot method name to a Swift Name + its definition
/// this list is used to generate later the proxies outside the class
///
func generateMethods (cdef: JGodotExtensionAPIClass, methods: [JGodotClassMethod], _ usedMethods: Set<String>) -> [String:(String, JGodotClassMethod)] {
    p ("/* Methods */")
    
    var virtuals: [String:(String, JGodotClassMethod)] = [:]
    
    for method in methods {
        let loc = "\(cdef.name).\(method.name)"
        if method.isVararg {
            print ("TODO: No vararg support yet \(loc)")
            continue
        }
        if (method.arguments ?? []).contains(where: { $0.type.contains("*")}) {
            print ("TODO: do not currently have support for C pointer types \(loc)")
            continue
        }
        if method.returnValue?.type.firstIndex(of: "*") != nil {
            print ("TODO: do not currently support C pointer returns \(loc)")
            continue
        }
        let bindName = "method_\(method.name)"
        
        var visibility: String
        var eliminate: String
        var finalp: String
        // Default method name
        var methodName: String = escapeSwift (snakeToCamel(method.name))
        
        let instanceOrStatic = method.isStatic ? " static" : ""
        var inline = ""
        if let methodHash = method.hash {
            assert (!method.isVirtual)
            b ("static var \(bindName): GDExtensionMethodBindPtr =", suffix: "()") {
                p ("let methodName = StringName (\"\(method.name)\")")
                
                /// TODO: make the handle in the generated bindings be an UnsafeRawPointer
                /// to avoid these casts here
                p ("return gi.classdb_get_method_bind (UnsafeRawPointer (&\(cdef.name).className.content), UnsafeRawPointer (&methodName.content), \(methodHash))!")
            }
            
            // If this is an internal, and being reference by a property, hide it
            if usedMethods.contains (method.name) {
                inline = "@inline(__always)"
                visibility = "private"
                eliminate = "_ "
                methodName = method.name
            } else {
                visibility = "public"
                eliminate = ""
            }
            if instanceOrStatic == "" {
                finalp = "final "
            } else {
                finalp = ""
            }
        } else {
            assert (method.isVirtual)
            // virtual overwrittable method
            finalp = ""
            visibility = "open"
            eliminate = ""
            var skip = false
            
            // TODO: for now, skip virtual methods that take an enum, since I do not convert those yet
            // nor do I handle creating a
            // - dictionary in the proxy: WebRTCPeerConnectionExtension._initialize
            // - strings
            // - bitfield; _ImageFormatLoaderExtension
            // - typedarray: CodeEdit
            for arg in method.arguments ?? [] {
                if arg.type.starts(with: "enum::") || arg.type == "Dictionary" || arg.type == "String" || arg.type.starts(with: "bitfield::") || arg.type.starts(with: "typedarray::") {
                    skip = true
                    break
                }
            }
            if skip {
                continue
            }
                
            virtuals [method.name] = (methodName, method)
        }
        
        var args = ""
        var argSetup = ""
        
        if let margs = method.arguments {
            for arg in margs {
                if args != "" { args += ", " }
                args += getArgumentDeclaration(arg, eliminate: eliminate)
                
                if argTypeNeedsCopy(godotType: arg.type) {
                    var reference = escapeSwift (snakeToCamel (arg.name))
                    // Wrap in an Int
                    if arg.type.starts(with: "enum::") {
                        reference = "Int64 (\(reference).rawValue)"
                    }
                    argSetup += "var copy_\(arg.name) = \(reference)\n"
                }
            }
            argSetup += "var args: [UnsafeRawPointer?] = [\n"
            for arg in margs {
                // When we move from GString to String in the public API
                //                if arg.type == "String" {
                //                    argSetup += "stringToGodotHandle (\(arg.name))\n"
                //                } else
                //                {
                var argref: String
                var optstorage: String
                var needAddress = "&"
                if argTypeNeedsCopy(godotType: arg.type) {
                    argref = "copy_\(arg.name)"
                    optstorage = ""
                } else {
                    argref = escapeSwift (snakeToCamel (arg.name))
                    if isStructMap [arg.type] ?? false {
                        optstorage = ""
                    } else {
                        if builtinSizes [arg.type] != nil && arg.type != "Object" || arg.type.starts(with: "typedarray::"){
                            optstorage = ".content"
                        } else {
                            optstorage = ".handle"
                            // No need to take the address for handles
                            needAddress = ""
                        }
                    }
                }
                
                argSetup += "    UnsafeRawPointer(\(needAddress)\(escapeSwift(argref))\(optstorage)),"
                //                }
            }
            argSetup += "]"
        }
        
        let godotReturnType = method.returnValue?.type
        let returnType = getGodotType (method.returnValue)
        
        if inline != "" {
            p (inline)
        }
        b ("\(visibility)\(instanceOrStatic) \(finalp)func \(methodName) (\(args))\(returnType != "" ? "-> " + returnType : "")") {
            if method.hash == nil {
                if let godotReturnType {
                    p (makeDefaultReturn (godotType: godotReturnType))
                }
            } else {
                if returnType != "" {
                    if godotReturnType?.starts(with: "typedarray::") ?? false {
                        p ("var _result: \(getBuiltinStorage ("Array"))")
                    } else {
                        p ("var _result: \(returnType) = \(makeDefaultInit(godotType: godotReturnType ?? ""))")
                    }
                }
                
                if argSetup != "" {
                    p (argSetup)
                }
                let ptrArgs = (args != "") ? "&args" : "nil"
                let ptrResult: String
                if returnType != "" {
                    if argTypeNeedsCopy(godotType: godotReturnType!) {
                        ptrResult = "&_result"
                    } else {
                        if godotReturnType!.starts (with: "typedarray::") || (builtinSizes [godotReturnType!] != nil && godotReturnType! != "Object") {
                            ptrResult = "&_result"
                        } else {
                            ptrResult = "&_result.handle"
                        }
                    }
                } else {
                    ptrResult = "nil"
                }
                
                let instanceHandle = method.isStatic ? "nil" : "UnsafeMutableRawPointer (mutating: handle)"
                p ("gi.object_method_bind_ptrcall (\(cdef.name).method_\(method.name), \(instanceHandle), \(ptrArgs), \(ptrResult))")
                
                if returnType != "" {
                    if godotReturnType?.starts(with: "typedarray::") ?? false {
                        let defaultInit = makeDefaultInit(godotType: godotReturnType!, initCollection: "content: _result")
                        
                        p ("return \(defaultInit)")
                    } else {
                        p ("return _result")
                    }
                }
            }
        }
    }
    if virtuals.count > 0 {
        b ("override class func getVirtualDispatcher (name: StringName) -> GDExtensionClassCallVirtual?"){
            b ("switch name.description") {
                for (name, _) in virtuals {
                    p ("case \"\(name)\":")
                    p ("    return _\(cdef.name)_proxy\(name)")
                }
                p ("default:")
                p ("    return super.getVirtualDispatcher (name: name)")
            }
        }
    }
    return virtuals
}


func generateProperties (cdef: JGodotExtensionAPIClass, _ properties: [JGodotProperty], _ methods: [JGodotClassMethod], _ referencedMethods: inout Set<String>)
{
    p ("\n/* Properties */\n")

    for property in properties {
        var type: String?
    
        // Ignore properties that only have getters, just let the setter
        // method be surfaced instead
        if property.getter == "" {
            print ("Property with only a setter: \(cdef.name).\(property.name)")
            continue
        }
        if property.getter.starts(with: "_") {
            // These exist, but have no equivalent method
            // see VisualShaderNodeParameterRef._parameter_type as an example
            continue
        }

//        // There are properties declared, but they do not actually exist
//        // CurveTexture claims to have a get_width, but the method does not exist
//        if type == nil {
//            continue
//        }
//        if type!.hasPrefix("Vector3.Axis") {
//            continue
//        }
        let loc = "\(cdef.name).\(property.name)"
        guard let method = methods.first(where: { $0.name == property.getter}) else {
            print ("WARNING \(loc): Could not find matching method for getter")
            continue
        }
        guard let setterMethod = methods.first(where: { $0.name == property.setter}) else {
            print ("WARNING \(loc) Could not find matching method for setter")
            continue
        }

        if method.arguments?.count ?? 0 > 1 {
            print ("WARNING \(loc) property references a getter method that takes more than one argument")
            continue
        }
        if setterMethod.arguments?.count ?? 0 > 2 {
            print ("WARNING \(loc) property references a getter method that takes more than two arguments")
            continue
        }
        if property.name == "positional_shadow_atlas_quad_0" {
            print ("a")
        }
        guard let returnType = method.returnValue?.type else {
            print ("WARNING \(loc) Could not get a return type for method")
            continue
        }
        // Lookup the type from the method, not the property,
        // sometimes the method is a GString, but the property is a StringName
        type = getGodotType (method.returnValue)

        // Ok, we have an indexer, this means we call the property with an int
        // but we need the type from the method
        var access: String
        if let idx = property.index {
            let type = getGodotType(method.arguments! [0])
            if type == "Int32" {
                access = "\(idx)"
            } else {
                access = "\(type) (rawValue: \(idx))!"
            }
        } else {
            access = ""
        }
        
        b ("final public var \(escapeSwift (snakeToCamel(property.name))): \(type!)"){
            b ("get"){
                p ("return \(property.getter) (\(access))")
            }
            referencedMethods.insert (property.getter)
            if let setter = property.setter {
                b ("set") {
                    var value = "newValue"
                    if type == "StringName" && setterMethod.arguments![0].type == "String" {
                        value = "GString (from: newValue)"
                    }
                    p ("\(setter) (\(access)\(access != "" ? ", " : "")\(value))")
                }
                referencedMethods.insert (setter)
            }
        }
    }
}

#if false
var okList = [ "RefCounted", "Node", "Sprite2D", "Node2D", "CanvasItem", "Object", "String", "StringName", "AStar2D", "Material", "Camera3D", "Node3D", "ProjectSettings", "MeshInstance3D", "BoxMesh", "SceneTree", "Window" ]
#else
var okList: [String] = []
#endif

func generateClasses (values: [JGodotExtensionAPIClass], outputDir: String) {
    // Assemble all the reference types, we use to test later
    for cdef in values {
        referenceTypes[cdef.name] = true
    }
    // Also a convenient hash to go from name to json
    // And track which types must be opened up
    for cdef in values {
        tree [cdef.name] = cdef
        
        let base = cdef.inherits ?? ""
        if base != "" {
            if var v = typeToChildren [cdef.name] {
                v.append(cdef.inherits ?? "")
            } else {
                typeToChildren [cdef.name] = [cdef.inherits ?? ""]
            }
        }
    }
    
    for cdef in values {
        // Clear the result
        result = ""
        p ("// Generated by Swift code generator - do not edit\nimport Foundation\nimport GDExtension\n")

        // Save it
        defer {
            try! result.write(toFile: outputDir + "/\(cdef.name).swift", atomically: true, encoding: .utf8)
        }
        
        let inherits = cdef.inherits ?? "Wrapped"
        let typeDecl = "open class \(cdef.name): \(inherits)"
        
        var virtuals: [String: (String, JGodotClassMethod)] = [:]
        // class or extension (for Object)
        b (typeDecl) {
            p ("static private var className = StringName (\"\(cdef.name)\")")
            b ("internal override init (nativeHandle: UnsafeRawPointer)") {
                p("super.init (nativeHandle: nativeHandle)")
            }
            b ("internal override init (name: StringName)") {
                p("super.init (name: name)")
            }
            
            let fastInitOverrides = cdef.inherits != nil ? "override " : ""
            
            b ("internal \(fastInitOverrides)init (fast: Bool)") {
                p ("super.init (name: \(cdef.name).className)")
            }
            b ("public required init ()") {
                p ("super.init (name: StringName (\"\(cdef.name)\"))")
            }
            
            var referencedMethods = Set<String>()
            
            if let enums = cdef.enums {
                generateEnums (values: enums)
            }

            let oResult = result

            if let properties = cdef.properties {
                generateProperties (cdef: cdef, properties, cdef.methods ?? [], &referencedMethods)
            }
            if let methods = cdef.methods {
                virtuals = generateMethods (cdef: cdef, methods: methods, referencedMethods)
            }
            
            // Remove code that we did not want generated
            if okList.count > 0 && !okList.contains (cdef.name) {
                result = oResult
            }
        }
        if virtuals.count > 0 {
            p ("// Support methods for proxies")
            for (_, (methodName, methodDef)) in virtuals {
                if okList.count == 0 || okList.contains (cdef.name) {
                    generateVirtualProxy(cdef: cdef, methodName: methodName, method: methodDef)
                }
            }
        }
        
    }
}

class Test {
    init (_ str: String) {}
}