//
//  IRBuilder.swift
//  DLVM
//
//  Created by Richard Wei on 12/18/16.
//
//

public class IRBuilder {
    public let module: Module
    public var currentBlock: BasicBlock?

    fileprivate var globalNameId: Int = 0
    fileprivate var nameIdTable: [String : Int] = [:]

    public init() {
        module = Module()
    }
}

// MARK: - Name generation and disambiguation
public extension IRBuilder {

    func makeName() -> String {
        return disambiguatedName(for: "v\(globalNameId)")
    }

    func disambiguatedName(for name: String) -> String {
        if let id = nameIdTable[name] {
            nameIdTable[name] = id + 1
            return name + ".\(id)"
        }
        nameIdTable[name] = 1
        return name
    }
    
}

// MARK: - Main builder API
public extension IRBuilder {

    @discardableResult
    public func declareTensor(named name: String, dataType: DataType,
                              shape: TensorShape) -> TensorVariable {
        let tensor = TensorVariable(name: name, dataType: dataType, shape: shape)
        module.declare(tensor)
        return tensor
    }

    @discardableResult
    public func declareScalar(named name: String,
                              type: ScalarType) -> ScalarVariable {
        let scalar = ScalarVariable(name: name, type: type)
        module.declare(scalar)
        return scalar
    }

    @discardableResult
    public func makeBasicBlock(named name: String) -> BasicBlock {
        let block = BasicBlock(name: disambiguatedName(for: name))
        currentBlock = block
        module.append(block)
        return block
    }

    @inline(__always)
    @discardableResult
    func build(_ instructionKind: Instruction.Kind, named name: String? = nil) -> Variable {
        precondition(currentBlock != nil, "Current basic block unavailable")
        let instruction = Instruction(kind: instructionKind)
        currentBlock!.append(instruction)
        return instruction.makeVariable(named: name ?? makeName())
    }

    /// Addition of the same type
    @discardableResult
    public func makeBinaryOperation<T: Variable>(
        _ `operator`: Instruction.BinaryOperator,
        _ lhs: T, _ rhs: T, name: String? = nil) -> T {
        return build(.binaryOp(`operator`, lhs, rhs), named: name) as! T
    }

    /// Addition of any operand with tensor
    @discardableResult
    public func makeBinaryOperation(
        _ `operator`: Instruction.BinaryOperator
        , _ lhs: Operand, _ rhs: TensorVariable, name: String? = nil) -> TensorVariable {
        return build(.binaryOp(`operator`, lhs, rhs), named: name) as! TensorVariable
    }

    /// Addition of any operand with tensor
    @discardableResult
    public func makeBinaryOperation(
        _ `operator`: Instruction.BinaryOperator
        , _ lhs: TensorVariable, _ rhs: Operand, name: String? = nil) -> TensorVariable {
        return build(.binaryOp(`operator`, lhs, rhs), named: name) as! TensorVariable
    }

    @discardableResult
    public func makeComparison(_ `operator`: Instruction.ComparisonOperator,
                               _ lhs: Operand, _ rhs: Operand,
                               name: String? = nil) -> ScalarVariable {
        return build(.compare(`operator`, lhs, rhs), named: name) as! ScalarVariable // bool
    }

    @discardableResult
    public func makeDotProduct(_ lhs: TensorVariable, _ rhs: TensorVariable,
                               name: String? = nil) -> TensorVariable {
        return build(.dotProduct(lhs, rhs), named: name) as! TensorVariable
    }

    @discardableResult
    public func makeProduct(_ lhs: TensorVariable, _ rhs: TensorVariable,
                            name: String? = nil) -> TensorVariable {
        return build(.product(lhs, rhs), named: name) as! TensorVariable
    }

    @discardableResult
    public func makeActivation(_ function: ActivationFunction, _ argument: TensorVariable,
                               name: String? = nil) -> TensorVariable {
        return build(.activation(function, argument), named: name) as! TensorVariable
    }

    @discardableResult
    public func makeTransformation(
        _ function: TransformationFunction, _ argument: TensorVariable,
        name: String? = nil) -> TensorVariable {
        return build(.transformation(function, argument), named: name) as! TensorVariable
    }

    @discardableResult
    public func makeConcatenation(
        _ arguments: [TensorVariable], name: String? = nil) -> TensorVariable {
        return build(.concat(arguments), named: name) as! TensorVariable
    }

    @discardableResult
    public func makePhi<T: Variable>(_ variables: T..., name: String? = nil) -> T {
        return build(.phi(variables), named: name) as! T
    }

    @discardableResult
    public func makeBranch(condition: Variable,
                           thenBlock: BasicBlock, elseBlock: BasicBlock) {
        build(.condBranch(condition, then: thenBlock, else: elseBlock))
    }

    @discardableResult
    public func makeBranch(_ block: BasicBlock) {
        build(.uncondBranch(block))
    }

}
