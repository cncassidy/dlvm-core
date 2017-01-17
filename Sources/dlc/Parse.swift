//
//  Parse.swift
//  DLVM
//
//  Created by Richard Wei on 12/22/16.
//
//

import Parsey
import func Funky.curry
import func Funky.flip

// ((a, b, c, d, e) -> f) -> a -> b -> c -> d -> e -> f
@inline(__always)
public func curry<A, B, C, D, E, F, G>(_ f: @escaping (A, B, C, D, E, F) -> G) -> (A) -> (B) -> (C) -> (D) -> (E) -> (F) -> G {
    return { w in { x in { y in { z in { a in { b in f(w, x, y, z, a, b) } } } } } }
}

/// Local primitive parsers
fileprivate let identifier = Lexer.regex("[a-zA-Z_][a-zA-Z0-9_.]*")
fileprivate let number = Lexer.unsignedInteger ^^ { Int($0)! } .. "a number"
fileprivate let lineComments = ("//" ~~> Lexer.string(until: ["\n", "\r"]).maybeEmpty() <~~
                                (newLines | Lexer.end))+
fileprivate let spaces = (Lexer.whitespace | Lexer.tab)+
fileprivate let comma = Lexer.character(",").amid(spaces.?) .. "a comma"
fileprivate let newLines = Lexer.newLine+
fileprivate let linebreaks = (newLines | lineComments).amid(spaces.?)+ .. "a linebreak"

protocol Parsible {
    static var parser: Parser<Self> { get }
}

extension TypeNode : Parsible {
    static let parser: Parser<TypeNode> =
        Lexer.character("f") ~~> number ^^^ TypeNode.float
      | Lexer.character("i") ~~> number ^^^ TypeNode.int
      | Lexer.character("b") ~~> number ^^^ TypeNode.bool
     .. "a data type"
}

extension ShapeNode : Parsible {
    static let parser: Parser<ShapeNode> =
        number.nonbacktracking().many(separatedBy: "x")
              .between(Lexer.character("["), Lexer.character("]").! .. "]")
    ^^^ ShapeNode.init
     .. "a shape"
}

extension ImmediateNode : Parsible {
    static let parser: Parser<ImmediateNode> =
        Lexer.signedDecimal ^^ { Double($0)! } ^^^ ImmediateNode.float
      | Lexer.signedInteger ^^ { Int($0)! } ^^^ ImmediateNode.int
      | ( Lexer.token("false") ^^= false
        | Lexer.token("true")  ^^= true  ) ^^^ ImmediateNode.bool
     .. "an immediate value"
}

extension ImmediateValueNode : Parsible {
    static let parser: Parser<ImmediateValueNode> =
        TypeNode.parser <~~ spaces ~~ ImmediateNode.parser.! ^^ ImmediateValueNode.init
     .. "an immediate value"
}

extension VariableNode : Parsible {
    static let parser: Parser<VariableNode> =
        Lexer.character("@") ~~> identifier.! ^^^ VariableNode.global
      | Lexer.character("%") ~~> identifier.! ^^^ VariableNode.temporary
      | ImmediateNode.parser.! ^^^ VariableNode.immediate
     .. "a variable"
}

extension OperandNode : Parsible {
    static let parser: Parser<OperandNode> =
        TypeNode.parser <~~ spaces ^^ curry(OperandNode.init)
     ** (ShapeNode.parser <~~ spaces).?
     ** VariableNode.parser
     .. "an operand"
}

import enum DLVM.ElementwiseFunction
import enum DLVM.ComparisonPredicate
import enum DLVM.AggregateFunction
import enum DLVM.ArithmeticOperator
import enum DLVM.ReductionFunction
import enum DLVM.ScanFunction
import enum DLVM.BinaryReductionFunction
import protocol DLVM.LexicallyConvertible

extension Parsible where Self : LexicallyConvertible {
    static var parser: Parser<Self> {
        return identifier.map(Self.lexicon)
    }
}

extension ElementwiseFunction : Parsible {}
extension ReductionFunction : Parsible {}
extension ScanFunction : Parsible {}
extension BinaryReductionFunction : Parsible {}
extension AggregateFunction : Parsible {}
extension ArithmeticOperator : Parsible {}
extension ComparisonPredicate : Parsible {}

extension InstructionNode : Parsible {

    private static let unaryParser: Parser<InstructionNode> =
      ( ElementwiseFunction.parser <~~ spaces ^^ curry(InstructionNode.elementwise)
      | AggregateFunction.parser <~~ spaces   ^^ curry(InstructionNode.aggregate)
      | "reduce" ~~> spaces ~~> ReductionFunction.parser.! <~~ spaces
                                              ^^ curry(InstructionNode.reduce)
      | "scan" ~~> spaces ~~> ScanFunction.parser.! <~~ spaces
                                              ^^ curry(InstructionNode.scan)
      | "load" ~~> spaces                     ^^= curry(InstructionNode.load)
      ) ** OperandNode.parser.!

    private static let binaryParser: Parser<InstructionNode> =
      ( BinaryReductionFunction.parser <~~ spaces
                                              ^^ curry(InstructionNode.binaryReduction)
      | ArithmeticOperator.parser <~~ spaces  ^^ curry(InstructionNode.arithmetic)
      | "compare" ~~> spaces ~~> ComparisonPredicate.parser.! <~~ spaces
                                              ^^ curry(InstructionNode.comparison)
      | "mmul" ~~> spaces                     ^^= curry(InstructionNode.matrixMultiply)
      | "tmul" ~~> spaces                     ^^= curry(InstructionNode.tensorMultiply)
      ) ** OperandNode.parser.! <~~ comma.! ** OperandNode.parser.!

    private static let concatParser: Parser<InstructionNode> =
        "concat" ~~> spaces ^^= curry(InstructionNode.concatenate)
     ** OperandNode.parser.nonbacktracking().many(separatedBy: comma)
     ** (Lexer.token("along").amid(spaces) ~~> number).?

    private static let shapeCastParser: Parser<InstructionNode> =
        "shapecast" ~~> spaces ^^= curry(InstructionNode.shapeCast)
     ** OperandNode.parser.! <~~ Lexer.token("to").amid(spaces)
     ** ShapeNode.parser

    private static let typeCastParser: Parser<InstructionNode> =
        "typecast" ~~> spaces ^^= curry(InstructionNode.typeCast)
     ** OperandNode.parser.! <~~ Lexer.token("to").amid(spaces)
     ** TypeNode.parser

    private static let storeParser: Parser<InstructionNode> =
        "store" ~~> spaces ^^= curry(InstructionNode.store)
     ** OperandNode.parser.! <~~ Lexer.token("to").amid(spaces)
     ** OperandNode.parser.!

    static let parser: Parser<InstructionNode> = unaryParser
                                               | binaryParser
                                               | concatParser
                                               | shapeCastParser
                                               | typeCastParser
                                               | storeParser
                                              .. "an instruction"
}

extension InstructionDeclarationNode : Parsible {
    static let parser: Parser<InstructionDeclarationNode> =
        spaces.? ~~> (Lexer.character("%") ~~> identifier <~~ Lexer.character("=").amid(spaces.?)).?
     ^^ curry(InstructionDeclarationNode.init)
     ** InstructionNode.parser
}

extension BasicBlockNode : Parsible {
    static let parser: Parser<BasicBlockNode> =
        identifier <~~ spaces.? ^^ curry(BasicBlockNode.init)
     ** (Lexer.token("gradient").amid(spaces.?).between("(", ")") ^^= true).withDefault(false)
    <~~ Lexer.character(":").amid(spaces.?).! <~~ linebreaks.!
     ** InstructionDeclarationNode.parser.!
                                  .many(separatedBy: linebreaks)
     .. "a basic block"
}

extension DeclarationNode.Role : Parsible {
    static let parser: Parser<DeclarationNode.Role> =
        Lexer.token("input")     ^^= .input
      | Lexer.token("parameter") ^^= .parameter
      | Lexer.token("output")    ^^= .output
     .. "a global variable role (input, parameter, output)"
}

extension Initializer : Parsible {
    static let parser: Parser<Initializer> =
        ImmediateValueNode.parser ^^^ Initializer.immediate
      | Lexer.token("repeating") ~~> spaces ~~> ImmediateValueNode.parser.! ^^^ Initializer.repeating
      | Lexer.token("random") ~~> Lexer.token("from").amid(spaces) ~~>
        ImmediateValueNode.parser.! ^^ curry(Initializer.random)
        ** (Lexer.token("to").amid(spaces) ~~> ImmediateValueNode.parser.!)
     .. "an initializer"
}

extension DeclarationNode : Parsible {
    static let parser: Parser<DeclarationNode> =
        Lexer.token("declare") ~~> Role.parser.amid(spaces.!) ^^ curry(DeclarationNode.init)
     ** TypeNode.parser.! <~~ spaces
     ** ShapeNode.parser.! <~~ spaces
     ** (Lexer.character("@") ~~> identifier).! .. "an identifier"
     ** (Lexer.character("=").amid(spaces.?) ~~> Initializer.parser.!).?
     .. "a declaration"
}

extension ModuleNode : Parsible {
    static let parser: Parser<ModuleNode> =
        linebreaks.? ~~> Lexer.token("module") ~~> spaces ~~> identifier.! ^^ curry(ModuleNode.init)
     ** DeclarationNode.parser.manyOrNone(separatedBy: linebreaks).amid(linebreaks.?)
     ** BasicBlockNode.parser.manyOrNone(separatedBy: linebreaks).ended(by: linebreaks.?)
     .. "a basic block"
}