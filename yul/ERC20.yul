object "ERC20" {
    code {
        // Constructor args are appended to the contract's code
        // We trust the calldata is correct
        // example: name = "Token", symbol = "TK"
        // name offset => nbArgs * 0x20 bytes because it's the first dynamic length argument
        // 0000000000000000000000000000000000000000000000000000000000000040
        // symbol offset => (nbArgs + (name.len / 0x20) + 0x1 + 0x1) * 0x20
        // 0000000000000000000000000000000000000000000000000000000000000080
        // name len
        // 0000000000000000000000000000000000000000000000000000000000000005
        // name data
        // 546f6b656e000000000000000000000000000000000000000000000000000000
        // symbol len
        // 0000000000000000000000000000000000000000000000000000000000000002
        // symbol data
        // 544b000000000000000000000000000000000000000000000000000000000000

        // Get the creation code size
        let contractSize := datasize("ERC20")
        // Calculate the constructor arguments size
        let argsSize := sub(codesize(), contractSize)
        // Copy encoded args to memory
        codecopy(0x00, contractSize, argsSize)
        // Store name arg to slot 0
        memStringArgToSlot(0x00)
        // Store symbol arg to slot 1
        memStringArgToSlot(0x01)
        // Store caller to slot 3
        sstore(0x03, caller())

        // Return the runtime bytecode
        datacopy(0x00, dataoffset("runtime"), datasize("runtime"))
        return(0x00, datasize("runtime"))

        /* --- storage layout --- */

        // function nameSlot() -> slot { slot := 0 }
        // function symbolSlot() -> slot { slot := 1 }
        // function ownerSlot() -> slot { slot := 3 }

        /* --- storage helpers --- */

        function memStringArgToSlot(argIndex) {
            // Get the string len offset
            let offset := mload(mul(argIndex, 0x20))
            // Load the arg len
            let len := mload(offset)
            // If len < 32, we can store the entire string and its len in the slot
            if lt(len, 0x20) {
                // Load the string data onto the stack
                let data := mload(add(offset, 0x20))
                // Add to it (i.e. append) the len * 2 (i.e. shl 1)
                let compactString := add(data, shl(0x01, len))
                // Store it to its slot
                sstore(argIndex, compactString)
                // Exit function
                leave
            }
            // Else
            // Store len * 2 + 1 at slot and string data at keccak256(slot)
            let slotData := add(shl(0x01, len), 0x01)
            sstore(argIndex, slotData)
            // Store string data starting keccak256(slot)
            mstore(0x00, argIndex)
            let startingDataSlot := keccak256(0x00, 0x20)
            // How many words are needed to store the string ? len / 32 + 1
            let neededWords := add(div(len, 0x20), 0x01)
            // Store all data words starting at the keccak256(slot)
            let stopAt := add(neededWords, 0x01)
            let offsetWithoutLen := add(offset, 0x20)
            for { let i := 0x00 } lt(i, stopAt) { i := add(i, 0x01) } {
                // Load the string data word onto the stack
                let data := mload(add(offsetWithoutLen, mul(i, 0x20)))
                sstore(add(startingDataSlot, i), data)
            }
        }
    }

    object "runtime" {
        code {
            // Extract the called function by getting the first 4 bytes of calldata
            let selector := shr(0xe0, calldataload(0x00))
            // Dispatcher
            switch selector
            // Case ordering is important for gas optimisations
            case 0x23b872dd /* "transferFrom(address,address,uint256)" */ {
                transferFrom(decodeAsAddress(0), decodeAsAddress(1), decodeAsUint(2))
                returnTrue()
            }
            case 0x095ea7b3 /* "approve(address,uint256)" */ {
                approve(decodeAsAddress(0), decodeAsUint(1))
                returnTrue()
            }
            case 0xa9059cbb /* transfer(address,uint256) */ {
                transfer(caller(), decodeAsAddress(0), decodeAsUint(1))
                returnTrue()
            }
            // Actions
            // Authorized actions
            case 0x40c10f19 /* "mint(address,uint256)" */ {
                // Check only owner can call this action
                require(calledByOwner())
                mint(decodeAsAddress(0), decodeAsUint(1))
                returnEmpty()
            }
            case 0x9dc29fac /* "burn(address,uint256)" */ {
                // Check only owner can call this action
                require(calledByOwner())
                burn(decodeAsAddress(0), decodeAsUint(1))
                returnEmpty()
            }
            // Getter functions
            case 0x06fdde03 /* "name()" */ {
                returnStorageString(nameSlot())
            }
            case 0x95d89b41 /* "symbol()" */ {
                returnStorageString(symbolSlot())
            }
            case 0x313ce567 /* "decimals()" */ {
                returnUint(0x12) // 18
            }
            case 0x18160ddd /* "totalSupply()" */ {
                returnUint(totalSupply())
            }
            case 0x8da5cb5b /* "owner()" */ {
                returnAddress(owner())
            }
            case 0x70a08231 /* "balanceOf(address)" */ {
                returnUint(balanceOf(decodeAsAddress(0)))
            }
            case 0xdd62ed3e /* "allowance(address,address)" */ {
                returnUint(allowance(decodeAsAddress(0), decodeAsAddress(1)))
            }
            default {
                revert(0x00, 0x00)
            }

            function transferFrom(from, to, value) {
                // Check underflow
                safeSubAllowance(from, caller(), value)
                // Transfer token
                transfer(from, to, value)
            }

            function approve(to, value) {
                setAllowance(caller(), to, value)
                emitApproval(caller(), to, value)
            }

            function transfer(from, to, value) {
                // Check underflow
                safeSubBalanceOf(from, value)
                // Cannot overflow here
                addBalanceOf(to, value)
                // Emit Transfer event
                emitTransfer(from, to, value)
            }

            function mint(to, amount) {
                // Check overflow
                setTotalSupply(safeAdd(totalSupply(), amount))
                // Add to balanceOf cannot overflow if setTotalSupply did not overflow
                addBalanceOf(to, amount)
                // Emit Transfer event
                emitTransfer(0x00, to, amount)
            }

            function burn(from, amount) {
                // Check underflow
                setTotalSupply(safeSub(totalSupply(), amount))
                // Sub to balanceOf
                subBalanceOf(from, amount)
                // Emit Transfer event
                emitTransfer(from, 0x00, amount)
            }

            /* --- calldata decoding/sanitization functions --- */

            function decodeAsUint(offset) -> u {
                // Calldata arg starts at offset * 32 bytes + 4 sig bytes
                let pos := add(0x04, mul(offset, 0x20))
                // We don't trust the input data
                // We check we can read 32 bytes in the calldata
                require(iszero(lt(calldatasize(), add(pos, 0x20))))
                u := calldataload(pos)
            }

            function decodeAsAddress(offset) -> a {
                a := decodeAsUint(offset)
                // We don't trust the input data
                // We check a is a valid uint160 value
                require(eq(a, and(a, 0xffffffffffffffffffffffffffffffffffffffff)))
            }

            /* --- calldata encoding functions --- */

            function returnEmpty() {
                return(0x00, 0x00)
            }

            function returnUint(u) {
                mstore(0x00, u)
                return(0x00, 0x20)
            }

            function returnTrue() {
                returnUint(0x01)
            }

            function returnAddress(addr) {
                returnUint(addr)
            }

            function returnStorageString(slot) {
                // Abi encoded string memory layout
                // example: "Token"
                // offset => nbArgs * 0x20 bytes because it's the first dynamic length argument
                // 0x00 => 0x0000000000000000000000000000000000000000000000000000000000000020
                // length
                // 0x20 => 0x0000000000000000000000000000000000000000000000000000000000000005
                // string data
                // 0x40 => 0x546f6b656e000000000000000000000000000000000000000000000000000000

                let startingMemPtr
                // Store offset
                mstore(startingMemPtr, 0x20)
                // Load the data in at slot
                let slotData := sload(slot)
                // Check if the string data is stored in the slot by checking if the last bit is 0
                if and(slotData, 0x01) {
                    /* Not Packed */
                    // Store length = slot data / 2 - 1 (i.e. shr 1)
                    let len := shr(0x01, slotData)
                    mstore(add(startingMemPtr, 0x20), len)
                    // Load string data starting keccak256(slot)
                    let dataMemPtr := add(startingMemPtr, 0x40)
                    mstore(dataMemPtr, slot)
                    let startingDataSlot := keccak256(dataMemPtr, 0x20)
                    // How many words are needed to store the string ? len / 32 + 1
                    let neededWords := add(div(len, 0x20), 0x01)
                    // Load all data words starting at the keccak256(slot)
                    for { let i := 0x00 } lt(i, neededWords) { i := add(i, 0x01) } {
                        // Load the string data word onto memory
                        let data := sload(add(startingDataSlot, i))
                        mstore(add(dataMemPtr, mul(i, 0x20)), data)
                    }
                    // return the starting memory pointer and size
                    return(0x00, add(0x40, mul(neededWords, 0x20)))
                }
                /* Packed */
                // Store length = last slot data byte / 2 (i.e. shr 1); (max = 31)
                mstore(add(startingMemPtr, 0x20), shr(0x01, byte(0x1f, slotData)))
                // Store data
                mstore(add(startingMemPtr, 0x40), slotData)
                // Clean the last byte (length)
                mstore8(add(startingMemPtr, 0x5f), 0x00)
                // return the starting memory pointer and size
                return(0x00, 0x60)
            }

            /* --- events functions --- */

            function emitTransfer(from, to, value) {
                // To log an event we must abi.encode the non indexed args in the data entry
                // In t1 we push the event.
                // Then add the bytes32 value or keccak256 hash of each indexed arg in a topic
                //
                // example: emit Transfer(address indexed from, address indexed to, uint256 value)
                // data: value in memory
                // t1: keccak256("Transfer(address,address,uint256)")
                // t2: from
                // t3: to
                mstore(0x00, value)
                log3(
                    0x00,
                    0x20,
                    0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef /* "Transfer(address,address,uint256)" */,
                    from,
                    to
                )
            }

            function emitApproval(from, to, value) {
                mstore(0x00, value)
                log3(
                    0x00,
                    0x20,
                    0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925 /* "Approval(address,address,uint256)" */,
                    from,
                    to
                )
            }

            /* --- storage layout --- */

            function nameSlot() -> slot { slot := 0 }
            function symbolSlot() -> slot { slot := 1 }
            function totalSupplySlot() -> slot { slot := 2 }
            function ownerSlot() -> slot { slot := 3 }
            function balanceOfSlot() -> slot { slot := 4 }
            function allowanceSlot() -> slot { slot := 5 }

            /* --- storage access functions --- */

            function name() -> n {
                n := sload(nameSlot())
            }

            function symbol() -> s {
                s := sload(symbolSlot())
            }

            function totalSupply() -> s {
                s := sload(totalSupplySlot())
            }

            function owner() -> o {
                o := sload(ownerSlot())
            }

            function balanceOf(addr) -> u {
                u := sload(getMappingValuePos(balanceOfSlot(), addr))
            }

            function allowance(from, to) -> u {
                u := sload(getNestedMappingValuePos(allowanceSlot(), from, to))
            }

            function setTotalSupply(value) {
                sstore(totalSupplySlot(), value)
            }

            function addBalanceOf(to, value) {
                let valuePos := getMappingValuePos(balanceOfSlot(), to)
                sstore(valuePos, add(sload(valuePos), value))
            }

            function subBalanceOf(to, value) {
                let valuePos := getMappingValuePos(balanceOfSlot(), to)
                sstore(valuePos, sub(sload(valuePos), value))
            }

            // Code duplication = more expensive to deploy but cheaper in execution
            function safeSubBalanceOf(to, value) {
                let valuePos := getMappingValuePos(balanceOfSlot(), to)
                sstore(valuePos, safeSub(sload(valuePos), value))
            }

            function setAllowance(from, to, value) {
                sstore(
                    getNestedMappingValuePos(allowanceSlot(), from, to),
                    value
                )
            }

            function safeSubAllowance(from, to, value) {
                let nestedValuePos := getNestedMappingValuePos(allowanceSlot(), from, to)
                sstore(nestedValuePos, safeSub(sload(nestedValuePos), value))
            }

            function getMappingValuePos(slot, key) -> pos {
                // We assume here key is a value type
                // We can get a mapping value position in storage by doing keccak256(valueTypeKey.concat(mappingSlot))
                mstore(0x00, key)
                mstore(0x20, slot)
                pos := keccak256(0x00, 0x40)
            }

            function getNestedMappingValuePos(slot, firstKey, secondKey) -> pos {
                // We assume here keys are value types
                // We can get a nested mapping value position in storage by doing keccak256(valueTypeSecondKey.concat(keccak256(valueTypeFirstKey.concat(mappingSlot))))
                pos := getMappingValuePos(
                    getMappingValuePos(slot, firstKey),
                    secondKey
                )
            }

            /* --- utility functions --- */

            function safeAdd(a, b) -> c {
                c := add(a, b)
                // Check overflow
                require(iszero(lt(c, a)))
            }

            function safeSub(a, b) -> c {
                c := sub(a, b)
                // Check underflow
                require(iszero(gt(c, a)))
            }

            function calledByOwner() -> c {
                c := eq(caller(), owner())
            }

            function require(condition) {
                if iszero(condition) { revert(0x00, 0x00) }
            }
        }
    }
}
